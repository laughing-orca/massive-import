# class CreateMassiveImportTables < ActiveRecord::Migration[8.1]
#   def change
#     create_table :massive_import_imports do |t|
#       t.column :attempt, :tinyint, null: false, default: 1
#       t.column :status, :string, limit: 50, default: 'PENDING'
#       t.column :total_records, :bigint, null: false, default: 0
#       t.column :batch_records, :bigint, null: false, default: 0
#       t.column :max_batch_concurrency, :smallint, null: false, default: 5
#       t.column :current_batch_concurrency, :smallint, null: false, default: 0
#       t.column :max_attempts, :tinyint, null: false, default: 3
#       t.column :batch_size, :smallint, null: false, default: 50
#       t.column :end_id, :bigint, null: false, default: 0
#       t.text :processor_class
#       t.column :planner_locked_until, :bigint
#       t.text :planner_token
#     end
#
#     create_table :massive_import_batches do |t|
#       t.column :import_id, :bigint, null: false
#       t.column :attempt, :tinyint, null: false, default: 1
#       t.column :status, :string, limit: 50, default: 'PENDING'
#       t.column :start_id, :bigint, null: false, default: 0
#       t.column :end_id, :bigint, null: false, default: 0
#       t.column :started_at, :bigint
#       t.text :token
#     end
#
#     add_index :massive_import_batches, [:import_id, :attempt, :status], name: 'idx_import_attempt_status'
#
#     create_table :massive_import_records do |t|
#       t.column :import_id, :bigint, null: false
#       t.column :attempt, :tinyint, null: false, default: 1
#       t.column :status, :string, limit: 50, default: 'PENDING'
#       t.json   :data
#     end
#
#     add_index :massive_import_records, [:import_id, :attempt, :status], name: 'idx_import_attempt_status'
#   end
# end
