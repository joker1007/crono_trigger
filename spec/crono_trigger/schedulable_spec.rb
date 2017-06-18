require "spec_helper"

RSpec.describe CronoTrigger::Schedulable do
  let(:notification1) do
    Notification.create!(
      name: "notification1",
      crontab: "0,30 * * * *",
      started_at: Time.current,
    )
  end
  let(:notification2) do
    Notification.create!(
      name: "notification2",
      crontab: "10 * * * *",
      started_at: Time.current,
    )
  end
  let(:notification3) do
    Notification.create!(
      name: "notification3",
      crontab: "*/10 * * * *",
      started_at: Time.current,
    )
  end
  let(:notification4) do
    Notification.create!(
      name: "notification4",
      crontab: "*/10 * * * *",
      started_at: Time.current,
    )
  end

  describe "before_create callback" do
    it "calculate_next_execute_at" do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 30))
      end
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
  end

  describe ".executables_with_lock" do
    it "fetch executable records with execute_lock update" do
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

  describe "#do_execute" do
    it "call #execute and update next_execute_at" do
      Timecop.freeze(Time.utc(2017, 6, 18, 0, 59)) do
        notification1
      end

      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        aggregate_failures do
          expect(notification1.next_execute_at).to eq(Time.utc(2017, 6, 18, 1, 0))
          expect(Notification.results).to be_empty

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
  end
end
