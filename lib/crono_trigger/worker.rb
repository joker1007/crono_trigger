require "active_support/core_ext/string"

module CronoTrigger
  module Worker
    def initialize
      @stop_flag = ServerEngine::BlockingFlag.new
      @model_queue = Queue.new
      @model_names = CronoTrigger.config.model_names || CronoTrigger::Schedulable.included_by
      @model_names.each do |model_name|
        @model_queue << model_name
      end
      @executor = Concurrent::ThreadPoolExecutor.new(
        min_threads: 1,
        max_threads: CronoTrigger.config.executor_thread,
      )
      ActiveRecord::Base.logger = logger
    end

    def run
      polling_thread_count = CronoTrigger.config.polling_thread || [@model_names.size, Concurrent.processor_count].min
      polling_threads = polling_thread_count.times.map { PollingThread.new(@model_queue, @stop_flag, logger, @executor) }
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
