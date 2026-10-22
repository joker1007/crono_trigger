require "spec_helper"
require "crono_trigger/web"

RSpec.describe CronoTrigger::Web do
  let(:request) { Rack::MockRequest.new(CronoTrigger::Web) }

  after do
    CronoTrigger::Models::Signal.delete_all
  end

  describe "POST /signals" do
    it "creates a signal" do
      response = request.post("/signals", params: {worker_id: "worker1", signal: "TSTP"})

      expect(response.status).to eq(200)
      expect(CronoTrigger::Models::Signal.where(worker_id: "worker1", signal: "TSTP")).to be_exists
    end

    it "returns 422 for an unsupported signal" do
      response = request.post("/signals", params: {worker_id: "worker1", signal: "KILL"})

      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)).to eq({"error" => "KILL signal is not supported"})
      expect(CronoTrigger::Models::Signal.count).to eq(0)
    end

    it "returns 422 without worker_id" do
      response = request.post("/signals", params: {signal: "TSTP"})

      expect(response.status).to eq(422)
    end
  end
end
