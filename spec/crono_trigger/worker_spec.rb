require "spec_helper"

RSpec.describe CronoTrigger::Worker do
  before do
    stub_const("CronoTrigger::Worker::HEARTBEAT_INTERVAL", 0.5)
    stub_const("CronoTrigger::Worker::SIGNAL_FETCH_INTERVAL", 0.5)
  end

  let(:worker) { Class.new { include CronoTrigger::Worker }.new }
  let(:worker_run) do
    unless worker.stopped?
      th = Thread.start { worker.run }
      until worker.polling_threads
        sleep 0.1
      end
      th
    end
  end

  after do
    worker.stop
    worker_run&.join
  end

  describe "#run" do
    it "starts polling threads" do
      expect(CronoTrigger::Models::Worker.count).to eq(0)
      worker_run
      expect(worker.polling_threads.size).to eq(1)
      expect(worker.polling_threads[0]).to be_a(CronoTrigger::PollingThread)
      expect(worker.polling_threads[0]).to be_alive
    end

    it "register worker" do
      expect(CronoTrigger::Models::Worker.count).to eq(0)
      worker_run
      alive_workers = CronoTrigger::Models::Worker.alive_workers.to_a
      expect(alive_workers.size).to eq(1)
      expect(alive_workers[0].worker_id).to eq(Socket.ip_address_list.detect { |info| !info.ipv4_loopback? && !info.ipv6_loopback? }.ip_address)
      expect(alive_workers[0].max_thread_size).to eq(25)
      expect(alive_workers[0].current_executing_size).to eq(0)
      expect(alive_workers[0].current_queue_size).to eq(0)
      expect(alive_workers[0].executor_status).to eq("running")
      expect(alive_workers[0].last_heartbeated_at).to be_a(Time)
    end

    it "quiet polling thread when give signal TSTP" do
      worker_run
      sleep 1
      expect(worker.polling_threads.size).to eq(1)
      expect(worker.polling_threads[0]).not_to be_quiet
      Process.kill(:TSTP, Process.pid)
      sleep 1
      expect(worker.polling_threads[0]).to be_quiet
    end

    it "handle signal from RDB operation" do
      worker_run
      sleep 1
      expect(worker.polling_threads[0]).not_to be_quiet
      CronoTrigger::Models::Signal.send_tstp(CronoTrigger.config.worker_id)
      sleep 2
      expect(worker.polling_threads[0]).to be_quiet
    end

    describe "error handling" do
      context "failed to register worker" do
        before do
          expect(CronoTrigger::Models::Worker).to receive(:find_or_initialize_by)
            .with(worker_id: CronoTrigger.config.worker_id)
            .and_raise(ActiveRecord::StatementInvalid)
        end

        it "call global_error_handlers" do
          assert_calling_global_error_handlers
          worker.send(:heartbeat)
        end
      end
    end
  end
end
