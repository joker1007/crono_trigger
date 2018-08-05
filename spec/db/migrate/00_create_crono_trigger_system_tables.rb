if ActiveRecord.version < Gem::Version.new("5.0.0")
  class CreateCronoTriggerSystemTables < ActiveRecord::Migration
    def change
      create_table :crono_trigger_workers, id: :string, primary_key: :worker_id do |t|
        t.datetime :last_heartbeated_at, null: false
      end

      add_index :crono_trigger_workers, :last_heartbeated_at
    end
  end
else
  class CreateCronoTriggerSystemTables < ActiveRecord::Migration[5.0]
    def change
      create_table :crono_trigger_workers, id: :string, primary_key: :worker_id do |t|
        t.datetime :last_heartbeated_at, null: false
      end

      add_index :crono_trigger_workers, :last_heartbeated_at
    end
  end
end
