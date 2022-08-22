require "spec_helper"

RSpec.describe CronoTrigger::PollingThread do
  let(:notification1) do
    Notification.create!(
      name: "notification1",
      cron: "0,30 * * * *",
      started_at: Time.current,
    ).tap(&:activate_schedule!)
  end
  let(:notification2) do
    Notification.create!(
      name: "notification2",
      cron: "10 * * * *",
      started_at: Time.current,
    ).tap(&:activate_schedule!)
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

  let(:immediate_executor_class_with_fallabck_policy) do
    Class.new(Concurrent::ImmediateExecutor) do
      def initialize(*args, **kwargs)
        super
        @fallback_policy = :caller_runs
      end
    end
  end

  describe "#run" do
    let(:stop_flag) { ServerEngine::BlockingFlag.new }
    let(:model_queue) { Queue.new.tap { |q| q << "Notification" } }
    let(:executor) { immediate_executor_class_with_fallabck_policy.new }
    subject(:polling_thread) { CronoTrigger::PollingThread.new(model_queue, stop_flag, Logger.new($stdout), executor, Concurrent::AtomicFixnum.new) }

    before do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        notification1
        notification2
        notification3
        notification4.update(finished_at: Time.current + 1)
      end
    end

    context "any exception is occured" do
      it "call global_error_handlers" do
        assert_calling_global_error_handlers
        expect(Notification).to receive(:executables_with_lock).and_raise(ActiveRecord::StatementInvalid.new)

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 10)) do
          polling_thread.run
          sleep CronoTrigger.config.polling_interval + 0.1
        end
        stop_flag.set!
        polling_thread.join
      end
    end
  end

  describe "#poll" do
    subject(:polling_thread) { CronoTrigger::PollingThread.new(Queue.new, ServerEngine::BlockingFlag.new, Logger.new($stdout), executor, Concurrent::AtomicFixnum.new) }

    let(:executor) { immediate_executor_class_with_fallabck_policy.new }
    let(:processed_records_from_instrument) { [] }

    around do |example|
      ActiveSupport::Notifications.subscribe(CronoTrigger::Events::PROCESS_RECORD) do |*_, payload|
        processed_records_from_instrument << payload[:record]
      end

      example.run

      ActiveSupport::Notifications.unsubscribe(CronoTrigger::Events::PROCESS_RECORD)
    end

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
        expect(processed_records_from_instrument).to contain_exactly(notification2, notification3)
      end
    end

    context "overflow executor queue size" do
      let(:executor) { Concurrent::ThreadPoolExecutor.new(max_threads: 1, max_queue: 1, fallback_policy: :caller_runs) }

      it "execute model#execute method" do
        Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
          # This notification will be processed by the caller
          notification1 # next_execute_at: 01:30:00 UTC

          # The folollowing notifications will be processed by the executor threads
          notification2 # next_execute_at: 01:10:00 UTC
          notification3 # next_execute_at: 01:10:00 UTC

          # This notification will never be processed
          notification4.update(finished_at: Time.current + 1)
        end

        Timecop.freeze(Time.utc(2017, 6, 18, 1, 30)) do
          expect(Notification.executables).to match_array([notification1, notification2, notification3])
          expect {
            polling_thread.poll(Notification)
            executor.shutdown
            executor.wait_for_termination
          }.to change { Notification.results }.from({}).to({notification2.id => "executed", notification3.id => "executed", notification1.id => "executed"})
          expect(processed_records_from_instrument).to contain_exactly(notification1, notification2, notification3)
        end
      end
    end

    if ENV["DB"] == "mysql"
      context "when MySQL is restarted after poll is called" do
        it "execute model#execute method without any errors" do
          Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
            notification1
            notification2
            notification3
            notification4.update(finished_at: Time.current + 1)
          end

          Timecop.freeze(Time.utc(2017, 6, 18, 1, 10)) do
            expect {
              th = Thread.start do
                polling_thread.poll(Notification)
                system(ENV["MYSQL_RESTART_COMMAND"])
                expect {
                  polling_thread.poll(Notification)
                }.to_not raise_error
              end
              th.join
            }.to change { Notification.results }.from({}).to({notification2.id => "executed", notification3.id => "executed"})
            expect(processed_records_from_instrument).to contain_exactly(notification2, notification3)
          end
        end
      end
    end
  end
end
