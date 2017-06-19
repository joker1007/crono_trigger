class <%= migration_class_name %> < ActiveRecord::Migration<%= Rails::VERSION::MAJOR >= 5 ? "[#{ActiveRecord::Migration.current_version}]" : "" %>
  def change
    # columns for CronoTrigger::Schedulable
    add_column :<%= table_name %>, :crontab, :string
    add_column :<%= table_name %>, :next_execute_at, :datetime
    add_column :<%= table_name %>, :last_executed_at, :datetime
    add_column :<%= table_name %>, :execute_lock, :integer, limit: 8, default: 0, null: false
    add_column :<%= table_name %>, :started_at, :datetime, null: false
    add_column :<%= table_name %>, :finished_at, :datetime
    add_column :<%= table_name %>, :last_error_name, :string
    add_column :<%= table_name %>, :last_error_reason, :string
    add_column :<%= table_name %>, :last_error_time, :string
    add_column :<%= table_name %>, :retry_count, :integer, default: 0, null: false
  end
end
