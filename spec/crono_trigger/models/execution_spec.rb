require "spec_helper"

RSpec.describe CronoTrigger::Models::Execution do
  let(:notification) do
    Notification.create!(
      name: "notification1",
      cron: "0,30 * * * *",
      started_at: Time.current,
    ).tap(&:activate_schedule!)
  end

  describe ".create_with_timestamp", aggregate_failures: true do
    subject { notification.crono_trigger_executions.create_with_timestamp! }

    it "creates record with current time as executed_at" do
      time = Time.utc(2017, 6, 18, 1, 0)
      Timecop.freeze(time) do
        is_expected.to be_persisted
        expect(subject.executed_at).to eq(time)
        expect(subject.status).to eq("executing")
        expect(subject.worker_id).to eq(CronoTrigger.config.worker_id)
      end
    end
  end

  describe "#complete!" do
    let(:execution) { notification.crono_trigger_executions.create_with_timestamp! }

    it "update (status = completed, completed_at = now)" do
      time1 = Time.utc(2017, 6, 18, 1, 0)
      Timecop.freeze(time1) do
        execution
      end

      time2 = Time.utc(2017, 6, 18, 2, 0)
      Timecop.freeze(time2) do
        execution.complete!
      end

      expect(execution.completed_at).to eq(time2)
      expect(execution.status).to eq("completed")
    end
  end

  describe "#error!" do
    let(:execution) { notification.crono_trigger_executions.create_with_timestamp! }

    it "update (status = failed, error_name = ex.class_name, error_reason = ex.message)" do
      time1 = Time.utc(2017, 6, 18, 1, 0)
      Timecop.freeze(time1) do
        execution
      end

      time2 = Time.utc(2017, 6, 18, 2, 0)
      Timecop.freeze(time2) do
        execution.error!(RuntimeError.new("failed!!"))
      end

      expect(execution.completed_at).to eq(time2)
      expect(execution.status).to eq("failed")
      expect(execution.error_name).to eq("RuntimeError")
      expect(execution.error_reason).to eq("failed!!")
    end
  end
end
