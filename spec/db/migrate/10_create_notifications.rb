class CreateNotifications < ActiveRecord::VERSION::MAJOR >= 5 ? ActiveRecord::Migration[5.0] : ActiveRecord::Migration
  def self.up
    create_table :notifications do |t|
      t.string :name
      t.string :cron
      t.datetime :next_execute_at
      t.datetime :last_executed_at
      t.string   :timezone
      t.integer  :execute_lock, limit: 8, default: 0, null: false
      t.string   :locked_by
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :last_error_name
      t.string :last_error_reason
      t.datetime :last_error_time
      t.string :current_cycle_id, null: false
      t.integer :retry_count, default: 0, null: false

      if ENV["NO_TIMESTAMP"] != "true"
        t.timestamps null: false
      end
    end
    add_index :notifications, [:next_execute_at, :execute_lock, :started_at, :finished_at], name: "crono_trigger_index_on_notifications"
  end
end
