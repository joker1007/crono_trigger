require "active_support/core_ext/string"

module CronoTrigger
  module Worker
    HEARTBEAT_INTERVAL = 60
    attr_reader :polling_threads

    def initialize
      @crono_trigger_worker_id = CronoTrigger.config.worker_id
      @stop_flag = ServerEngine::BlockingFlag.new
      @heartbeat_stop_flag = ServerEngine::BlockingFlag.new
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
      run_heartbeat_thread

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
      @executor.wait_for_termination

      unregister
    end

    def stop
      @stop_flag.set!
      @heartbeat_stop_flag.set!
    end

    def stopped?
      @stop_flag.set?
    end

    private

    def run_heartbeat_thread
      heartbeat
      Thread.start do
        loop do
          until @heartbeat_stop_flag.wait_for_set(HEARTBEAT_INTERVAL)
            heartbeat
          end
        end
      end
    end

    def heartbeat
      worker_record = CronoTrigger::Models::Worker.find_or_initialize_by(worker_id: @crono_trigger_worker_id)
      worker_record.last_heartbeated_at = Time.current
      @logger.info("[worker_id:#{@crono_trigger_worker_id}] Send heartbeat to database")
      worker_record.save
    rescue => ex
      p ex
      stop
    end

    def unregister
      @logger.info("[worker_id:#{@crono_trigger_worker_id}] Unregister worker from database")
      CronoTrigger::Models::Worker.find_by(worker_id: @crono_trigger_worker_id)&.destroy
    end
  end
end
