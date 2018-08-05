class CreateCronoTriggerSystemTables < ActiveRecord::Migration<%= Rails::VERSION::MAJOR >= 5 ? "[#{ActiveRecord::Migration.current_version}]" : "" %>
  def change
    create_table :crono_trigger_workers, id: :string, primary_key: :worker_id do |t|
      t.datetime :last_heartbeated_at, null: false
    end

    add_index :crono_trigger_workers, :last_heartbeated_at
  end
end
