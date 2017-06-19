require "rails/generators/active_record/model/model_generator"

module CronoTrigger
  module Generators
    class ModelGenerator < ActiveRecord::Generators::ModelGenerator
      source_root File.expand_path("../templates", __FILE__)

      desc "Create model for Scheduled Job"
    end
  end
end
