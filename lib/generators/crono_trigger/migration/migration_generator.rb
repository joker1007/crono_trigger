require "rails/generators/active_record/migration/migration_generator"

module CronoTrigger
  module Generators
    class MigrationGenerator < ActiveRecord::Generators::MigrationGenerator
      source_root File.expand_path("../templates", __FILE__)

      desc "Create migration for Scheduled Job"
    end
  end
end
