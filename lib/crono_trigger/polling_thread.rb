module CronoTrigger
  class PollingThread
    def initialize(model_queue, stop_flag, logger, executor, execution_counter)
      @model_queue = model_queue
      @stop_flag = stop_flag
      @logger = logger
      @executor = executor
      if @executor.fallback_policy != :caller_runs
        raise ArgumentError, "executor's fallback policies except for :caller_runs are not supported"
      end
      @execution_counter = execution_counter
      @quiet = Concurrent::AtomicBoolean.new(false)
      @worker_count = 1
    end

    def run
      @thread = Thread.start do
        @logger.info "(polling-thread-#{Thread.current.object_id}) Start polling thread"
        until @stop_flag.wait_for_set(CronoTrigger.config.polling_interval)
          next if quiet?

          CronoTrigger.reloader.call do
            begin
              model_name = @model_queue.pop(true)
              model = model_name.classify.constantize
              poll(model)
            rescue ThreadError => e
              @logger.error(e) unless e.message == "queue empty"
            rescue => ex
              @logger.error(ex)
              CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
            ensure
              @model_queue << model_name if model_name
            end
          end
        end
      end
    end

    def join
      @thread.join
    end

    def quiet
      @quiet.make_true
    end

    def quiet?
      @quiet.true?
    end

    def alive?
      @thread.alive?
    end

    def poll(model)
      @logger.info "(polling-thread-#{Thread.current.object_id}) Poll #{model}"

      maybe_has_next = true
      while maybe_has_next && !@stop_flag.set?
        records, maybe_has_next = model.connection_pool.with_connection do
          model.executables_with_lock(limit: CronoTrigger.config.fetch_records || CronoTrigger.config.executor_thread * 3, worker_count: @worker_count)
        end

        records.each do |record|
          @executor.post do
            @execution_counter.increment
            begin
              process_record(record)
            ensure
              @execution_counter.decrement
            end
          end
        end
      end
    end

    def worker_count=(n)
      raise ArgumentError, "worker_count must be greater than 0" if n <= 0
      @worker_count = n
    end

    private

    def process_record(record)
      ActiveSupport::Notifications.instrument(CronoTrigger::Events::PROCESS_RECORD, { record: record }) do
        record.class.connection_pool.with_connection do
          @logger.info "(executor-thread-#{Thread.current.object_id}) Execute #{record.class}-#{record.id}"
          record.do_execute
        end
      end
    rescue Exception => ex
      @logger.error(ex)
      CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
    end
  end
end
