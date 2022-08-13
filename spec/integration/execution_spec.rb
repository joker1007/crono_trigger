require "spec_helper"

RSpec.describe "Execute records" do
  let(:worker_class) do
    Class.new do
      include CronoTrigger::Worker

      def initialize
        @logger = Logger.new(nil)
        super
      end
    end
  end

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
      worker = worker_class.new
      Thread.start { worker.run }
      sleep CronoTrigger.config.polling_interval + 2

      expect(Notification.executables).not_to be_exists
    ensure
      worker.stop
    end
  end
end
