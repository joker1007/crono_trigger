require "spec_helper"
require "crono_trigger/web"

RSpec.describe CronoTrigger::Web do
  let(:request) { Rack::MockRequest.new(CronoTrigger::Web) }

  after do
    CronoTrigger::Models::Signal.delete_all
    CronoTrigger::Models::Worker.delete_all
  end

  describe "GET /workers.json" do
    it "returns alive workers" do
      Timecop.freeze(Time.utc(2017, 6, 18, 1, 0)) do
        CronoTrigger::Models::Worker.create!(
          worker_id: "worker1",
          max_thread_size: 25,
          current_executing_size: 1,
          current_queue_size: 0,
          executor_status: "running",
          polling_model_names: ["Notification"],
          last_heartbeated_at: Time.current,
        )

        response = request.get("/workers.json")

        expect(response.status).to eq(200)
        expect(response.content_type).to start_with("application/json")
        expect(JSON.parse(response.body)).to eq({
          "records" => [{
            "worker_id" => "worker1",
            "max_thread_size" => 25,
            "current_executing_size" => 1,
            "current_queue_size" => 0,
            "executor_status" => "running",
            "polling_model_names" => ["Notification"],
            "last_heartbeated_at" => "2017-06-18T01:00:00.000Z",
          }],
        })
      end
    end
  end

  describe "GET /models.json" do
    it "returns model names" do
      response = request.get("/models.json")

      expect(response.status).to eq(200)
      expect(JSON.parse(response.body)).to eq({"models" => ["Notification"]})
    end
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
