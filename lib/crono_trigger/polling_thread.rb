module CronoTrigger
  class PollingThread
    def initialize(model_queue, stop_flag, logger, executor)
      @model_queue = model_queue
      @stop_flag = stop_flag
      @logger = logger
      @executor = executor
    end

    def run
      @thread = Thread.start do
        @logger.info "(polling-thread-#{Thread.current.object_id}) Start polling thread"
        until @stop_flag.wait_for_set(CronoTrigger.config.polling_interval)
          begin
            model = @model_queue.pop(true)
            poll(model)
          rescue ThreadError => e
            @logger.error(e) unless e.message == "queue empty"
          rescue => e
            @logger.error(e)
          ensure
            @model_queue << model if model
          end
        end
      end
    end

    def join
      @thread.join
    end

    def poll(model)
      @logger.debug "(polling-thread-#{Thread.current.object_id}) Poll #{model}"
      records = []
      primary_key_offset = nil
      begin
        begin
          conn = model.connection_pool.checkout
          records = model.executables_with_lock(primary_key_offset: primary_key_offset)
          primary_key_offset = records.last && records.last.id
        ensure
          model.connection_pool.checkin(conn)
        end

        records.each do |record|
          @executor.post do
            model.connection_pool.with_connection do
              @logger.info "(executor-thread-#{Thread.current.object_id}) Execute #{record.class}-#{record.id}"
              begin
                record.do_execute
              rescue Exception => e
                @logger.error(e)
              end
            end
          end
        end
      end while records.any?
    end
  end
end
