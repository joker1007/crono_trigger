require "active_support/core_ext/string"

require "crono_trigger/global_exception_handler"

module CronoTrigger
  module Worker
    HEARTBEAT_INTERVAL = 60
    SIGNAL_FETCH_INTERVAL = 10
    MONITOR_INTERVAL = 20
    WORKER_COUNT_UPDATE_INTERVAL = 60
    EXECUTOR_SHUTDOWN_TIMELIMIT = 300
    OTHER_THREAD_SHUTDOWN_TIMELIMIT = 120
    attr_reader :polling_threads

    def initialize
      @crono_trigger_worker_id = CronoTrigger.config.worker_id
      @stop_flag = ServerEngine::BlockingFlag.new
      @heartbeat_stop_flag = ServerEngine::BlockingFlag.new
      @signal_fetch_stop_flag = ServerEngine::BlockingFlag.new
      @monitor_stop_flag = ServerEngine::BlockingFlag.new
      @model_queue = Queue.new
      @model_names = CronoTrigger.config.model_names || CronoTrigger::Schedulable.included_by
      @model_names.each do |model_name|
        @model_queue << model_name
      end
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: CronoTrigger.config.executor_thread,
        max_queue: CronoTrigger.config.executor_thread * 2,
        fallback_policy: :caller_runs,
      )
      @execution_counter = Concurrent::AtomicFixnum.new
      @logger = Logger.new(STDOUT) unless @logger
      ActiveRecord::Base.logger = @logger
    end

    def run
      @heartbeat_thread = run_heartbeat_thread
      @signal_fetcn_thread = run_signal_fetch_thread
      @monitor_thread = run_monitor_thread
      @worker_count_updater_thread = run_worker_count_updater_thread

      polling_thread_count = CronoTrigger.config.polling_thread || [@model_names.size, Concurrent.processor_count].min
      # Assign local variable for Signal handling
      polling_threads = polling_thread_count.times.map { PollingThread.new(@model_queue, @stop_flag, @logger, @executor, @execution_counter) }
      @polling_threads = polling_threads
      @polling_threads.each(&:run)

      ServerEngine::SignalThread.new do |st|
        st.trap(:TSTP) do
          @logger.info("[worker_id:#{@crono_trigger_worker_id}] Transit to quiet mode")
          polling_threads.each(&:quiet)
          heartbeat
        end
      end

      @polling_threads.each(&:join)

      @executor.shutdown
      @executor.wait_for_termination(EXECUTOR_SHUTDOWN_TIMELIMIT)
      @heartbeat_thread.join(OTHER_THREAD_SHUTDOWN_TIMELIMIT)
      @signal_fetcn_thread.join(OTHER_THREAD_SHUTDOWN_TIMELIMIT)
      @worker_count_updater_thread.join(OTHER_THREAD_SHUTDOWN_TIMELIMIT)

      unregister
    end

    def stop
      @stop_flag.set!
      @heartbeat_stop_flag.set!
      @signal_fetch_stop_flag.set!
      @monitor_stop_flag.set!
    end

    def stopped?
      @stop_flag.set?
    end

    def quiet?
      @polling_threads&.all?(&:quiet?)
    end

    private

    def run_heartbeat_thread
      heartbeat
      Thread.start do
        until @heartbeat_stop_flag.wait_for_set(HEARTBEAT_INTERVAL)
          heartbeat
        end
      end
    end

    def run_signal_fetch_thread
      Thread.start do
        until @signal_fetch_stop_flag.wait_for_set(SIGNAL_FETCH_INTERVAL)
          handle_signal_from_rdb
        end
      end
    end

    def run_monitor_thread
      Thread.start do
        until @monitor_stop_flag.wait_for_set(MONITOR_INTERVAL)
          monitor
        end
      end
    end

    def run_worker_count_updater_thread
      update_worker_count
      Thread.start do
        until @stop_flag.wait_for_set(WORKER_COUNT_UPDATE_INTERVAL)
          update_worker_count
        end
      end
    end

    def heartbeat
      CronoTrigger::Models::Worker.connection_pool.with_connection do
        begin
          worker_record = CronoTrigger::Models::Worker.find_or_initialize_by(worker_id: @crono_trigger_worker_id)
          worker_record.max_thread_size = @executor.max_length
          worker_record.current_executing_size = @execution_counter.value
          worker_record.current_queue_size = @executor.queue_length
          worker_record.executor_status = executor_status
          worker_record.polling_model_names = @model_names
          worker_record.last_heartbeated_at = Time.current
          @logger.info("[worker_id:#{@crono_trigger_worker_id}] Send heartbeat to database")
          worker_record.save!
        rescue => ex
          CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
          stop
        end
      end
    end

    def executor_status
      case
      when @executor.shutdown?
        "shutdown"
      when @executor.shuttingdown?
        "shuttingdown"
      when @executor.running?
        if quiet?
          "quiet"
        else
          "running"
        end
      end
    end

    def unregister
      @logger.info("[worker_id:#{@crono_trigger_worker_id}] Unregister worker from database")
      CronoTrigger::Models::Worker.connection_pool.with_connection do
        CronoTrigger::Models::Worker.find_by(worker_id: @crono_trigger_worker_id)&.destroy
      end
    rescue => ex
      CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
    end

    def handle_signal_from_rdb
      CronoTrigger::Models::Signal.connection_pool.with_connection do
        CronoTrigger::Models::Signal.sent_to_me.take(1)[0]&.tap do |s|
          @logger.info("[worker_id:#{@crono_trigger_worker_id}] Receive Signal #{s.signal} from database")
          s.kill_me(to_supervisor: s.signal != "TSTP")
        end
      end
    rescue => ex
      CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
    end

    def monitor
      return unless ActiveSupport::Notifications.notifier.listening?(CronoTrigger::Events::MONITOR)

      CronoTrigger::Models::Worker.connection_pool.with_connection do
        if workers_processing_same_models.order(:worker_id).limit(1).pluck(:worker_id).first != @crono_trigger_worker_id
          # Return immediately to avoid redundant instruments
          return
        end

        @model_names.each do |model_name|
          model = model_name.classify.constantize
          executable_count = model.executables.limit(nil).count

          execute_lock_column = model.crono_trigger_column_name(:execute_lock)
          oldest_execute_lock = model.executables(including_locked: true).where.not(execute_lock_column => 0).order(execute_lock_column).limit(1).pluck(execute_lock_column).first

          next_execute_at_column = model.crono_trigger_column_name(:next_execute_at)
          oldest_next_execute_at = model.executables.order(next_execute_at_column).limit(1).pluck(next_execute_at_column).first

          now = Time.now
          ActiveSupport::Notifications.instrument(CronoTrigger::Events::MONITOR, {
            model_name: model_name,
            executable_count: executable_count,
            max_lock_duration_sec: oldest_execute_lock.nil? ? 0 : now.to_i - oldest_execute_lock,
            max_latency_sec: oldest_next_execute_at.nil? ? 0 : now - oldest_next_execute_at,
          })
        end
      end
    rescue => ex
      CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
    end

    def update_worker_count
      CronoTrigger::Models::Worker.connection_pool.with_connection do
        worker_count = workers_processing_same_models.count
        return if worker_count.zero?
        @polling_threads.each { |th| th.worker_count = worker_count }
      end
    rescue => ex
      CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
    end

    def workers_processing_same_models
      CronoTrigger.workers.where("polling_model_names = ?", @model_names.to_json)
    end
  end
end
