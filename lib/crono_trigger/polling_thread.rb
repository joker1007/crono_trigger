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
      @logger.info "(polling-thread-#{Thread.current.object_id}) Poll #{model}"

      queue_empty_event = Concurrent::Event.new
      maybe_has_next = true
      while maybe_has_next && !@stop_flag.set?
        queue_empty_event.wait unless @executor.queue_length.zero?
        records, maybe_has_next = model.connection_pool.with_connection do
          model.executables_with_lock(limit: @executor.remaining_capacity)
        end

        queue_empty_event.reset
        records.each do |record|
          @executor.post do
            @execution_counter.increment
            begin
              process_record(record)
            ensure
              @execution_counter.decrement
            end

            queue_empty_event.set if @executor.queue_length.zero?
          end
        end
      end
    end

    private

    def process_record(record)
      record.class.connection_pool.with_connection do
        @logger.info "(executor-thread-#{Thread.current.object_id}) Execute #{record.class}-#{record.id}"
        record.do_execute
      end
    rescue Exception => ex
      @logger.error(ex)
      CronoTrigger::GlobalExceptionHandler.handle_global_exception(ex)
    end
  end
end
