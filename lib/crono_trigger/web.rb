require "crono_trigger"
require "sinatra/base"
require "rack/contrib/post_body_content_type_parser"

module CronoTrigger
  class Web < Sinatra::Application
    use Rack::PostBodyContentTypeParser

    set :root, File.expand_path("../../../web", __FILE__)
    set :public_folder, Proc.new { File.join(root, "public") }
    set :views, proc { File.join(root, "views") }

    get "/" do
      erb :index
    end

    get "/workers:format?" do
      if params[:format] == ".json"
        content_type :json
        @workers = CronoTrigger::Models::Worker.alive_workers
        Oj.dump({
          records: @workers,
        }, mode: :compat)
      else
        erb :index
      end
    end

    post "/signals" do
      worker_id = params[:worker_id]
      sig = params[:signal]
      if worker_id && sig
        if CronoTrigger::Models::Signal.send_signal(sig, worker_id)
          status 200
          body ""
        else
          status 422
          Oj.dump({error: "#{sig} signal is not supported"}, mode: :compat)
        end
      else
        status 422
        Oj.dump({error: "Must set worker_id and signal"}, mode: :compat)
      end
    end

    get "/signals:format?" do
      if params[:format] == ".json"
        content_type :json
        @signals = CronoTrigger::Models::Signal.order(sent_at: :desc).limit(30)
        Oj.dump({
          records: @signals,
        }, mode: :compat)
      else
        erb :index
      end
    end

    get "/models/:name.:format" do
      models_handler
    end

    get "/models/:name" do
      models_handler
    end

    get "/models:format?" do
      if params[:format] == ".json"
        content_type :json
        @models = CronoTrigger::Schedulable.included_by.map(&:name).sort
        Oj.dump({
          models: @models,
        }, mode: :compat)
      else
        erb :index
      end
    end

    private

    def models_handler
      if params[:format] == "json"
        content_type :json
        model_class = CronoTrigger::Schedulable.included_by.find { |c| c.name == params[:name] }
        if model_class
          @scheduled_records = model_class.executables(limit: 100, including_locked: true).reorder(next_execute_at: :desc)
          Oj.dump({
            records: @scheduled_records.map { |r|
              r.as_json(methods: [:crono_trigger_status], only: [
                :id,
                :cron,
                :next_execute_at,
                :last_executed_at,
                :timezone,
                :execute_lock,
                :locked_by,
                :started_at,
                :finished_at,
                :last_error_name,
                :last_error_reason,
                :last_error_time,
                :retry_count
              ])
            },
          }, mode: :compat)
        else
          status 404
          "Model Class is not found"
        end
      else
        erb :index
      end
    end
  end
end
