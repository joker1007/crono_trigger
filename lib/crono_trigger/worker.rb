require "active_support/core_ext/string"

module CronoTrigger
  module Worker
    HEARTBEAT_INTERVAL = 60
    SIGNAL_FETCH_INTERVAL = 30
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
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: CronoTrigger.config.executor_thread,
      )
      @logger = Logger.new(STDOUT) unless @logger
      ActiveRecord::Base.logger = @logger
    end

    def run
      @heartbeat_thread = run_heartbeat_thread
      @signal_fetcn_thread = run_signal_fetch_thread

      polling_thread_count = CronoTrigger.config.polling_thread || [@model_names.size, Concurrent.processor_count].min
      # Assign local variable for Signal handling
      polling_threads = polling_thread_count.times.map { PollingThread.new(@model_queue, @stop_flag, @logger, @executor) }
      @polling_threads = polling_threads
      @polling_threads.each(&:run)

      ServerEngine::SignalThread.new do |st|
        st.trap(:TSTP) do
          @logger.info("[worker_id:#{@crono_trigger_worker_id}] Transit to quiet mode")
          polling_threads.each(&:quiet)
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
      worker_record = CronoTrigger::Models::Worker.find_or_initialize_by(worker_id: @crono_trigger_worker_id)
      worker_record.max_thread_size = @executor.max_length
      worker_record.current_executing_size = @executor.scheduled_task_count
      worker_record.current_queue_size = @executor.queue_length
      worker_record.executor_status = executor_status
      worker_record.last_heartbeated_at = Time.current
      @logger.info("[worker_id:#{@crono_trigger_worker_id}] Send heartbeat to database")
      worker_record.save
    rescue => ex
      p ex
      stop
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
      CronoTrigger::Models::Worker.find_by(worker_id: @crono_trigger_worker_id)&.destroy
    end

    def handle_signal_from_rdb
      CronoTrigger::Models::Signal.sent_to_me.take(1)[0]&.tap do |s|
        @logger.info("[worker_id:#{@crono_trigger_worker_id}] Receive Signal #{s.signal} from database")
        s.kill_me
      end
    end
  end
end
