require "spec_helper"

RSpec.describe CronoTrigger::Schedulable do
  let(:notification1) do
    Notification.create!(
      name: "notification1",
      cron: "0,30 * * * *",
      started_at: Time.current,
    ).tap(&:activate_schedule!)
  end
  let(:notification2) do
    Notification.new(
      name: "notification2",
      cron: "10 * * * *",
    ).tap(&:activate_schedule!).tap(&:save!)
  end
  let(:notification3) do
    Notification.create!(
      name: "notification3",
      cron: "*/10 * * * *",
      started_at: Time.current,
    ).tap(&:activate_schedule!)
  end
  let(:notification4) do
    Notification.create!(
      name: "notification4",
      cron: "*/10 * * * *",
      started_at: Time.current,
    ).tap(&:activate_schedule!)
  end
  let(:notification5) do
    Notification.new(
      name: "notification5",
      cron: "10 18 * * *",
      started_at: Time.current,
    ).tap(&:activate_schedule!).tap(&:save!)
  end
  let(:notification6) do
    Notification.create!(
      name: "notification6",
      cron: "10 18 * * *",
      timezone: "US/Pacific",
      started_at: Time.current,
    ).tap(&:activate_schedule!)
  end
  let(:notification7) do
    Notification.create!(
      name: "notification6",
      cron: "10 18 * * *",
      timezone: "US/Pacific",
      started_at: Time.current.since(2.day),
    ).tap(&:activate_schedule!)
  end

  describe "before_create callback" do
    it "calculate_next_execute_at" do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 30))
      end
    end
  end

  describe "before_update callback" do
    it "calculate_next_execute_at if update cron or timezone" do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        expect(notification5.next_execute_at).to eq(Time.utc(2017, 6, 18, 18, 10))
        notification5.update(cron: "45 18 * * *")
        expect(notification5.next_execute_at).to eq(Time.utc(2017, 6, 18, 18, 45))
        notification5.update(timezone: "Asia/Tokyo")
        expect(notification5.next_execute_at).to eq(Time.utc(2017, 6, 18, 9, 45))
      end
    end
  end

  describe "validation" do
    specify "cron_format validation" do
      notification = Notification.new(
        name: "notification1",
        cron: "a,30 * * * *",
        started_at: Time.current,
      )
      expect(notification).to be_invalid
      expect(notification.errors[:cron]).to be_present
    end
  end

  describe ".executables" do
    it "fetch executable records" do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        notification1
        notification2
        notification3
        notification4.update(finished_at: Time.current + 1)
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 10)) do
        expect(Notification.executables).to match_array([notification2, notification3])
      end
    end

    context "has executable_conditions" do
      after do
        Notification.send(:clear_executable_conditions)
      end

      it "filter by executable_conditions" do
        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          notification1
          notification2
          notification3
          notification4.update(finished_at: Time.current + 1)
        end

        Notification.send(:add_executable_conditions, -> { where(cron: "10 * * * *") })

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 10)) do
          expect(Notification.executables).to match_array([notification2])
        end
      end
    end
  end

  describe ".executables_with_lock" do
    it "fetch executable records with execute_lock update", aggregate_failures: true do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        notification1
        notification2
        notification3
        notification4.update(finished_at: Time.current + 1)
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 10)) do
        records = Notification.executables_with_lock(limit: 1)
        aggregate_failures do
          expect(records).to match_array([notification2])
          expect(records[0].reload.execute_lock).to eq(Time.current.to_i)
        end

        records = Notification.executables_with_lock(limit: 1)
        aggregate_failures do
          expect(records).to match_array([notification3])
          expect(records[0].reload.execute_lock).to eq(Time.current.to_i)
        end

        records = Notification.executables_with_lock(limit: 1)
        aggregate_failures do
          expect(records).to be_empty
        end
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 20)) do
        records = Notification.executables_with_lock(limit: 1)
        aggregate_failures do
          expect(records).to match_array([notification2])
          expect(records[0].reload.execute_lock).to eq(Time.current.to_i)
        end

        records = Notification.executables_with_lock(limit: 1)
        aggregate_failures do
          expect(records).to match_array([notification3])
          expect(records[0].reload.execute_lock).to eq(Time.current.to_i)
        end
      end
    end
  end

  describe "#calculate_next_execute_at" do
    it "consider timezone" do
      Timecop.freeze(Time.utc(2017, 6, 18, 17, 0)) do
        Time.use_zone("Asia/Tokyo") do
          aggregate_failures do
            expect(notification5.send(:calculate_next_execute_at)).to eq(Time.use_zone("Asia/Tokyo") { Time.zone.local(2017, 6, 19, 18, 10) })
            expect(notification6.send(:calculate_next_execute_at)).to eq(Time.use_zone(notification6.timezone) { Time.zone.local(2017, 6, 18, 18, 10) })
          end
        end
      end
    end

    it "consider started_at" do
      Timecop.freeze(Time.utc(2017, 6, 18, 17, 0)) do
        aggregate_failures do
          expect(notification7.send(:calculate_next_execute_at)).to eq(Time.use_zone(notification7.timezone) { Time.zone.local(2017, 6, 20, 18, 10) })
        end
      end
    end
  end

  describe "#do_execute" do
    it "call #execute and update next_execute_at" do
      Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
        notification1
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        aggregate_failures do
          expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
          expect(Notification.results).to be_empty
          expect(notification1).to receive(:after)

          notification1.do_execute

          notification1.reload

          expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 30))
          expect(notification1.last_executed_at).to eq(Time.utc(2017, 6, 18, 1, 0))
          expect(notification1.execute_lock).to eq(0)
          expect(Notification.results).to eq({notification1.id => "executed"})
        end
      end
    end

    context "#execute is error" do
      it "call #execute and #retry!" do
        Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
          notification1
        end

        allow(notification1).to receive(:execute).and_raise("Error")

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          aggregate_failures do
            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(Notification.results).to be_empty

            begin
              notification1.do_execute
            rescue
            end

            notification1.reload

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0, CronoTrigger::Schedulable::DEFAULT_RETRY_INTERVAL))
            expect(notification1.last_executed_at).to be_nil
            expect(notification1.execute_lock).to eq(0)
            expect(notification1.retry_count).to eq(1)
            expect(Notification.results).to be_empty
          end
        end
      end
    end

    context "#execute throw :abort" do
      it "call #execute and #reset!" do
        Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
          notification1
        end

        def notification1.execute
          throw :abort
          raise "Not reach"
        end

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          aggregate_failures do
            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(Notification.results).to be_empty

            expect { notification1.do_execute }.to raise_error(CronoTrigger::Schedulable::AbortExecution)

            notification1.reload

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 30))
            expect(notification1.last_executed_at).to be_nil
            expect(notification1.execute_lock).to eq(0)
            expect(notification1.retry_count).to eq(0)
            expect(notification1.last_error_name).to eq("CronoTrigger::Schedulable::AbortExecution")
            expect(notification1.last_error_time).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(Notification.results).to be_empty
          end
        end
      end
    end

    context "#execute throw :retry" do
      it "call #execute and #retry!" do
        Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
          notification1
        end

        def notification1.execute
          throw :retry
          raise "Not reach"
        end

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          aggregate_failures do
            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(Notification.results).to be_empty

            notification1.do_execute

            notification1.reload

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0, CronoTrigger::Schedulable::DEFAULT_RETRY_INTERVAL))
            expect(notification1.last_executed_at).to be_nil
            expect(notification1.execute_lock).to eq(0)
            expect(notification1.retry_count).to eq(1)
            expect(Notification.results).to be_empty
          end
        end
      end
    end

    context "#execute throw :ok" do
      it "call #execute and update next_execute_at and last_executed_at" do
        Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
          notification1
        end

        def notification1.execute
          throw :ok
          raise "Not reach"
        end

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          aggregate_failures do
            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(Notification.results).to be_empty

            notification1.update!(execute_lock: Time.now.to_i)
            notification1.do_execute

            notification1.reload

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 30))
            expect(notification1.last_executed_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(notification1.execute_lock).to eq(0)
            expect(notification1.retry_count).to eq(0)
            expect(Notification.results).to be_empty
          end
        end
      end
    end

    context "#execute throw :ok" do
      it "call #execute and update next_execute_at and last_executed_at" do
        Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
          notification1
        end

        def notification1.execute
          throw :ok_without_reset
          raise "Not reach"
        end

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          aggregate_failures do
            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(Notification.results).to be_empty

            notification1.update!(execute_lock: Time.now.to_i)
            notification1.do_execute

            notification1.reload

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(notification1.last_executed_at).to be_nil
            expect(notification1.execute_lock).to be > 0
            expect(notification1.retry_count).to eq(0)
            expect(Notification.results).to be_empty

            notification1.reset!

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 30))
            expect(notification1.last_executed_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(notification1.execute_lock).to eq(0)
            expect(notification1.retry_count).to eq(0)
          end
        end
      end
    end

    context "#execute raises error" do
      it "call #execute and call retry_or_reset!" do
        Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
          notification1
        end

        def notification1.execute
          raise "error"
        end

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          aggregate_failures do
            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(notification1.last_error_name).to be_nil
            expect(notification1.last_error_reason).to be_nil
            expect(notification1.last_error_time).to be_nil
            expect(Notification.results).to be_empty

            notification1.update!(execute_lock: Time.now.to_i)
            expect { notification1.do_execute }.to raise_error(RuntimeError)

            notification1.reload

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0) + CronoTrigger::Schedulable::DEFAULT_RETRY_INTERVAL)
            expect(notification1.last_executed_at).to be_nil
            expect(notification1.execute_lock).to eq(0)
            expect(notification1.retry_count).to eq(1)
            expect(notification1.last_error_name).to eq("RuntimeError")
            expect(notification1.last_error_reason).to eq("error")
            expect(notification1.last_error_time).to eq(Time.utc(2017, 6, 18, 1, 0))
            expect(Notification.results).to be_empty
          end
        end

        scope = {
          framework: "CronoTrigger: #{::CronoTrigger::VERSION}",
          context: "#{notification1.class}/#{notification1.id}"
        }
        rollbar_notifier = double(:rollbar_notifier)
        expect(Rollbar).to receive(:scope).with(scope) { rollbar_notifier }
        expect(rollbar_notifier).to receive(:error).with(a_kind_of(RuntimeError), use_exception_level_filters: true)

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0) + CronoTrigger::Schedulable::DEFAULT_RETRY_INTERVAL) do
          aggregate_failures do
            notification1.update!(execute_lock: Time.now.to_i)
            expect(notification1.instance_variable_get("@error")).to be_nil
            expect { notification1.do_execute }.to raise_error(RuntimeError)

            notification1.reload

            expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 30))
            expect(notification1.last_executed_at).to be_nil
            expect(notification1.execute_lock).to eq(0)
            expect(notification1.retry_count).to eq(0)
            expect(Notification.results).to eq({notification1.id => "error"})
            expect(notification1.instance_variable_get("@error")).to be_a(RuntimeError)
          end
        end
      end
    end
  end

  describe "#locking?" do
    it "return locking status as Boolean" do
      expect(notification1.locking?).to be_falsey
      locked_at = Time.utc(2017, 6, 18, 1, 0)
      notification1.execute_lock = locked_at.to_i
      expect(notification1.locking?(at: locked_at + Notification.execute_lock_timeout - 1)).to be_truthy
      expect(notification1.locking?(at: locked_at + Notification.execute_lock_timeout)).to be_falsey
    end
  end

  describe "#assume_executing?" do
    it "return locking status as Boolean" do
      expect(notification1.assume_executing?).to be_falsey

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        notification1.execute_lock = Time.now.to_i
        expect(notification1.assume_executing?).to be_truthy
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 10, 0) - 1) do
        expect(notification1.assume_executing?).to be_truthy
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 10, 1)) do
        expect(notification1.assume_executing?).to be_falsey
      end
    end
  end
end
