require "active_support/core_ext/string"

require "crono_trigger/global_exception_handler"

module CronoTrigger
  module Worker
    HEARTBEAT_INTERVAL = 60
    SIGNAL_FETCH_INTERVAL = 10
    EXECUTOR_SHUTDOWN_TIMELIMIT = 300
    OTHER_THREAD_SHUTDOWN_TIMELIMIT = 120
    attr_reader :polling_threads

    def initialize
      @crono_trigger_worker_id = CronoTrigger.config.worker_id
      @stop_flag = ServerEngine::BlockingFlag.new
      @heartbeat_stop_flag = ServerEngine::BlockingFlag.new
      @signal_fetch_stop_flag = ServerEngine::BlockingFlag.new
      @model_queue = Queue.new
      @model_names = CronoTrigger.config.model_names || CronoTrigger::Schedulable.included_by
      @model_names.each do |model_name|
        @model_queue << model_name
      end
      if CronoTrigger.config.executor_thread == 1
        # Don't use the thread pool executor, with which the caller can also
        # process tasks, because the reason why executor_thread is set to 1
        # might be that the application is not thread-safe.
        @executor = Concurrent::ImmediateExecutor.new
        def @executor.queue_length
          0
        end
      else
        @executor = Concurrent::ThreadPoolExecutor.new(
          min_threads: 1,
          max_threads: CronoTrigger.config.executor_thread,
          max_queue: CronoTrigger.config.executor_thread * 2,
          fallback_policy: :caller_runs,
        )
      end
      @execution_counter = Concurrent::AtomicFixnum.new
      @logger = Logger.new(STDOUT) unless @logger
      ActiveRecord::Base.logger = @logger
    end

    def run
      @heartbeat_thread = run_heartbeat_thread
      @signal_fetcn_thread = run_signal_fetch_thread

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

      unregister
    end

    def stop
      @stop_flag.set!
      @heartbeat_stop_flag.set!
      @signal_fetch_stop_flag.set!
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

    def heartbeat
      CronoTrigger::Models::Worker.connection_pool.with_connection do
        begin
          worker_record = CronoTrigger::Models::Worker.find_or_initialize_by(worker_id: @crono_trigger_worker_id)
          worker_record.max_thread_size = CronoTrigger.config.executor_thread
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
  end
end
