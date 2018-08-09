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

    get "/workers.:format" do
      if params[:format] == "json"
        content_type :json
        @workers = CronoTrigger::Models::Worker.alive_workers
        Oj.dump({
          records: @workers,
        }, mode: :compat)
      else
        raise "unknown format"
      end
    end

    get "/workers" do
      erb :index
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

    get "/signals.:format" do
      if params[:format] == "json"
        content_type :json
        @signals = CronoTrigger::Models::Signal.order(sent_at: :desc).limit(30)
        Oj.dump({
          records: @signals,
        }, mode: :compat)
      else
        raise "unknown format"
      end
    end

    get "/signals" do
      erb :index
    end

    post "/models/:name/:id/unlock" do
      model_class = CronoTrigger::Schedulable.included_by.find { |c| c.name == params[:name] }
      if model_class
        model_class.find(params[:id]).update_columns(execute_lock: 0, locked_by: nil)
        status 200
        body ""
      else
        status 404
        "Model Class is not found"
      end
    end

    post "/models/:name/:id/reset" do
      model_class = CronoTrigger::Schedulable.included_by.find { |c| c.name == params[:name] }
      if model_class
        model_class.find(params[:id]).reset!
        status 200
        body ""
      else
        status 404
        "Model Class is not found"
      end
    end

    post "/models/:name/:id/retry" do
      model_class = CronoTrigger::Schedulable.included_by.find { |c| c.name == params[:name] }
      if model_class
        model_class.find(params[:id]).retry!
        status 200
        body ""
      else
        status 404
        "Model Class is not found"
      end
    end

    get "/models/:name.:format" do
      models_handler
    end

    get "/models/:name" do
      erb :index
    end

    get "/models.:format" do
      if params[:format] == "json"
        content_type :json
        @models = CronoTrigger::Schedulable.included_by.map(&:name).sort
        Oj.dump({
          models: @models,
        }, mode: :compat)
      else
        raise "unknown format"
      end
    end

    get "/models" do
      erb :index
    end

    private

    def models_handler
      if params[:format] == "json"
        content_type :json
        model_class = CronoTrigger::Schedulable.included_by.find { |c| c.name == params[:name] }
        if model_class
          @scheduled_records = model_class.executables(limit: 100, including_locked: true).reorder(next_execute_at: :desc)
          @scheduled_records.where!(locked_by: params[:worker_id]) if params[:worker_id]
          now = Time.now
          records = @scheduled_records.map do |r|
            {
              "crono_trigger_status" => r.crono_trigger_status,
              "id" => r.id,
              "cron" => r[r.crono_trigger_column_name(:cron)],
              "next_execute_at" => r[r.crono_trigger_column_name(:next_execute_at)],
              "last_executed_at" => r[r.crono_trigger_column_name(:last_executed_at)],
              "timezone" => r[r.crono_trigger_column_name(:timezone)],
              "execute_lock" => r[r.crono_trigger_column_name(:execute_lock)],
              "locked_by" => r[r.crono_trigger_column_name(:locked_by)],
              "started_at" => r[r.crono_trigger_column_name(:started_at)],
              "finished_at" => r[r.crono_trigger_column_name(:finished_at)],
              "last_error_name" => r[r.crono_trigger_column_name(:last_error_name)],
              "last_error_reason" => r[r.crono_trigger_column_name(:last_error_reason)],
              "last_error_time" => r[r.crono_trigger_column_name(:last_error_time)],
              "retry_count" => r[r.crono_trigger_column_name(:retry_count)],
              "time_to_unlock" => [(r.class.execute_lock_timeout + r[r.crono_trigger_column_name(:execute_lock)]) - now.to_i, 0].max,
              "delay_sec" => r.locking?(at: now) ? 0 : (now - r[r.crono_trigger_column_name(:next_execute_at)]).to_i,
            }
          end
          Oj.dump({
            records: records,
          }, mode: :compat)
        else
          status 404
          "Model Class is not found"
        end
      else
        raise "unknown format"
      end
    end
  end
end
