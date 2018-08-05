require "spec_helper"

RSpec.describe CronoTrigger::Worker do
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
    end

    it "quiet polling thread when give signal TSTP" do
      worker_run
      sleep 1
      expect(worker.polling_threads.size).to eq(1)
      Process.kill(:TSTP, Process.pid)
      sleep 1
      expect(worker.polling_threads[0]).to be_quiet
    end
  end
end
