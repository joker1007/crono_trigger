if ActiveRecord.version < Gem::Version.new("5.0.0")
  class CreateNotifications < ActiveRecord::Migration
    def change
      create_table :notifications do |t|
        t.string :name
        t.string :crontab
        t.datetime :next_execute_at
        t.datetime :last_executed_at
        t.integer  :execute_lock, limit: 8, default: 0, null: false
        t.datetime :started_at, null: false
        t.datetime :finished_at
        t.string :last_error_name
        t.string :last_error_reason
        t.datetime :last_error_time
        t.integer :retry_count, default: 0, null: false

        t.timestamps null: false
      end
      add_index :notifications, [:next_execute_at, :execute_lock, :started_at, :finished_at], name: "crono_trigger_index_on_notifications"
    end
  end
else
  class CreateNotifications < ActiveRecord::Migration[5.0]
    def change
      create_table :notifications do |t|
        t.string :name
        t.string :crontab
        t.datetime :next_execute_at
        t.datetime :last_executed_at
        t.integer  :execute_lock, limit: 8, default: 0, null: false
        t.datetime :started_at, null: false
        t.datetime :finished_at
        t.datetime :finished_at
        t.string :last_error_name
        t.string :last_error_reason
        t.datetime :last_error_time
        t.integer :retry_count, default: 0, null: false

        t.timestamps null: false
      end
      add_index :notifications, [:next_execute_at, :execute_lock, :started_at, :finished_at], name: "crono_trigger_index_on_notifications"
    end
  end
end
