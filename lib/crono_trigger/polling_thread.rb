module CronoTrigger
  class PollingThread
    def initialize(model_queue, stop_flag, logger, executor, execution_counter)
      @model_queue = model_queue
      @stop_flag = stop_flag
      @logger = logger
      @executor = executor
      @execution_counter = execution_counter
      @quiet = Concurrent::AtomicBoolean.new(false)
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
      @logger.debug "(polling-thread-#{Thread.current.object_id}) Poll #{model}"
      records = []
      overflowed_record_ids = []

      begin
        model.connection_pool.with_connection do
          records = model.executables_with_lock
        end

        records.each do |record|
          begin
            @executor.post do
              @execution_counter.increment
              begin
                process_record(record)
              ensure
                @execution_counter.decrement
              end
            end
          rescue Concurrent::RejectedExecutionError
            overflowed_record_ids << record.id
          end
        end
        unlock_overflowed_records(model, overflowed_record_ids)
      end while overflowed_record_ids.empty? && records.any?
    end

    private 

    def process_record(record)
      record.class.connection_pool.with_connection do
        @logger.info "(executor-thread-#{Thread.current.object_id}) Execute #{record.class}-#{record.id}"
        record.do_execute
      end
    end

    def unlock_overflowed_records(model, overflowed_record_ids)
      model.connection_pool.with_connection do
        unless overflowed_record_ids.empty?
          model.where(id: overflowed_record_ids).crono_trigger_unlock_all!
        end
      end
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::LockWaitTimeout, ActiveRecord::StatementTimeout, ActiveRecord::Deadlocked
      sleep 1
      retry
    end
  end
end
