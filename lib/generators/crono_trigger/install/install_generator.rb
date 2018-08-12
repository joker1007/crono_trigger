require "rails/generators/active_record/migration"

module CronoTrigger
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("../templates", __FILE__)

      desc "Create migration for CronoTrigger System Table"
      def create_migration_file
        migration_template "install.rb", File.join(db_migrate_path, "create_crono_trigger_system_tables.rb")
      end
    end
  end
end
