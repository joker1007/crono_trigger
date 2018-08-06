require "crono_trigger"
require "sinatra/base"

module CronoTrigger
  class Web < Sinatra::Base
    set :root, File.expand_path("../../../web", __FILE__)
    set :public_folder, Proc.new { File.expand_path("#{root}/assets") }
    set :views, proc { File.join(root, "views") }

    get "/" do
      redirect "/workers"
    end

    get "/workers" do
      @workers = CronoTrigger::Models::Worker.alive_workers
      erb :workers
    end

    get "/signals" do
      @signals = CronoTrigger::Models::Signal.order(sent_at: :desc).limit(30)
      erb :signals
    end
  end
end
