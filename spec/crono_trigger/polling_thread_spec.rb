require "spec_helper"

RSpec.describe CronoTrigger::PollingThread do
  let(:notification1) do
    Notification.create!(
      name: "notification1",
      cron: "0,30 * * * *",
      started_at: Time.current,
    )
  end
  let(:notification2) do
    Notification.create!(
      name: "notification2",
      cron: "10 * * * *",
      started_at: Time.current,
    )
  end
  let(:notification3) do
    Notification.create!(
      name: "notification3",
      cron: "*/10 * * * *",
      started_at: Time.current,
    )
  end
  let(:notification4) do
    Notification.create!(
      name: "notification4",
      cron: "*/10 * * * *",
      started_at: Time.current,
    )
  end

  describe "#poll" do
    subject(:polling_thread) { CronoTrigger::PollingThread.new(Queue.new, ServerEngine::BlockingFlag.new, Logger.new($stdout), executor) }

    let(:executor) { Concurrent::ImmediateExecutor.new }

    it "execute model#execute method" do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        notification1
        notification2
        notification3
        notification4.update(finished_at: Time.current + 1)
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 10)) do
        expect {
          polling_thread.poll(Notification)
        }.to change { Notification.results }.from({}).to({notification2.id => "executed", notification3.id => "executed"})
      end
    end
  end
end
