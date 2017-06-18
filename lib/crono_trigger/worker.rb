require "active_support/core_ext/string"

module CronoTrigger
  module Worker
    def initialize
      @stop_flag = ServerEngine::BlockingFlag.new
      @model_queue = Queue.new
      CronoTrigger.config.model_names.each do |model_name|
        model = model_name.classify.constantize
        @model_queue << model
      end
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: CronoTrigger.config.executor_thread,
      )
      ActiveRecord::Base.logger = logger
    end

    def run
      polling_threads = CronoTrigger.config.polling_thread.times.map { PollingThread.new(@model_queue, @stop_flag, logger, @executor) }
      polling_threads.each(&:run)
      polling_threads.each(&:join)

      @executor.shutdown
      @executor.wait_for_termination
    end

    def stop
      @stop_flag.set!
    end
  end
end
