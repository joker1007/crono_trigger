require "spec_helper"

RSpec.describe "Execute records" do
  let(:worker_class) do
    Class.new do
      include CronoTrigger::Worker

      def initialize(logger)
        @logger = logger
        super()
      end
    end
  end
  let(:logger) { Logger.new(log_buffer) }
  let(:log_buffer) { StringIO.new }

  context "when there are so many records that the execution queue reaches the maximum size" do
    around do |example|
      original_polling_interval = CronoTrigger.config.polling_interval
      CronoTrigger.config.polling_interval = 2

      example.run

      CronoTrigger.config.polling_interval = original_polling_interval
    end

    before do
      allow_any_instance_of(Notification).to receive(:execute) do
        sleep 1
      end

      now = Time.now
      # executor.max_length + executor.max_queue + 1
      76.times do |i|
        Notification.create!(name: i.to_s, started_at: now, next_execute_at: now)
      end
    end

    it "processes all the records without returning from #poll" do
      worker = worker_class.new(logger)
      Thread.start { worker.run }
      sleep CronoTrigger.config.polling_interval + 2

      expect(Notification.executables).not_to be_exists
    ensure
      worker.stop
    end
  end

  context "when all the executable records are locked" do
    around do |example|
      original_polling_interval = CronoTrigger.config.polling_interval
      CronoTrigger.config.polling_interval = 2

      example.run

      CronoTrigger.config.polling_interval = original_polling_interval
    end

    before do
      now = Time.now
      Notification.create!(name: 'notification', started_at: now, next_execute_at: now)
    end

    it "processes all the records without returning from #poll" do
      allow_any_instance_of(Notification).to receive(:locking?) do
        allow_any_instance_of(Notification).to receive(:locking?) { false }
        true
      end

      worker = worker_class.new(logger)
      Thread.start { worker.run }
      sleep CronoTrigger.config.polling_interval + 1

      expect(Notification.executables).not_to be_exists
    ensure
      worker.stop
    end
  end

  context "when the workers receive SIGTERM while processing records" do
    before do
      now = Time.now
      Notification.create!(name: 'notification', started_at: now, next_execute_at: now)
    end

    it "stops the worker" do
      # Make maybe_has_next true
      allow_any_instance_of(Notification).to receive(:locking?) { true }

      worker = worker_class.new(logger)
      Thread.start do
        sleep CronoTrigger.config.polling_interval + 1
        worker.stop
      end
      Timeout.timeout(CronoTrigger.config.polling_interval + 2) { worker.run }
    end
  end

  context "when the concurrency is 1" do
    around do |example|
      original_executor_thread = CronoTrigger.config.executor_thread
      CronoTrigger.config.executor_thread = 1

      example.run

      CronoTrigger.config.executor_thread = original_executor_thread
    end

    before do
      now = Time.now
      Notification.create!(name: 'notification', started_at: now, next_execute_at: now)
    end

    it "processes records using the polling thread" do
      worker = worker_class.new(logger)
      Thread.start { worker.run }
      sleep CronoTrigger.config.polling_interval + 1

      expect(Notification.executables).not_to be_exists

      polling_thread_id = log_buffer.string.slice(/polling-thread-(\d+)/, 1)
      expect(polling_thread_id).not_to be_nil
      executor_thread_id = log_buffer.string.slice(/executor-thread-(\d+)/, 1)
      expect(executor_thread_id).to eq(polling_thread_id)
    ensure
      worker.stop
    end
  end
end
