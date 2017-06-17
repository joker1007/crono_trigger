require "crono_trigger/version"

require 'concurrent'

module CronoTrigger
  module Scheduler
    def run
      execute_pool = Concurrent::ThreadPoolExecutor.new(
        min_threads: 25,
        max_threads: 25,
        max_queue: 10000,
      )

      @model_queue = Queue.new

      polling_threads = 5.map do 
        Thread.new do
          until @stop
            begin
              model = @model_queue.pop(true)
              model.connection_pool.with_connection do
                model.executables.find_in_batches do |records|
                  model.where(id: records.map(&:id)).update_all(execute_lock: Time.current.to_i)
                  execute_pool.post do
                    model.connection_pool.with_connection do
                      record.do_execute
                    end
                  end
                end
              end
            rescue ThreadError => e
              logger.error(e) unless e.message == "queue empty"
            rescue => e
              logger.error(e)
            ensure
              @model_queue << model if model
            end

            sleep 5
          end
        end
      end

      polling_threads.each(&:join)
      execute_pool.shutdown
      execute_pool.wait_on_termination
    end

    def stop
      @stop = true
    end
  end
end
