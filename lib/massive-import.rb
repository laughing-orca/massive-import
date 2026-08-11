require 'active_record'
require 'sidekiq'
require 'logger'

require_relative 'massive-import/planner_job'
require_relative 'massive-import/processor_job'
require_relative 'massive-import/dashboard_server'


module MassiveImport
  class Configuration
    attr_accessor :queue_name, :batch_timeout, :planning_interval, :planner_lease

    def initialize
      unless ActiveRecord::Base.connected?
        ActiveRecord::Base.establish_connection(
          adapter:  'mysql2',
          host:     ENV['host'],
          username: ENV['username'],
          password: ENV['password'],
          database: ENV['database']
        )
      end
      ActiveRecord::Base.logger ||= Logger.new($stdout)
    end

    def queue_name
      @queue_name || :default
    end

    def batch_timeout
      @batch_timeout || 900
    end

    def planning_interval
      @planning_interval || 5
    end

    def planner_lease
      @planner_lease || 900
    end
  end

# CREATE TABLE `massive_import_imports` (
#   `id` bigint unsigned NOT NULL AUTO_INCREMENT,
#   `attempt` tinyint NOT NULL DEFAULT 1,
#   `status` varchar(50) DEFAULT 'PENDING',
#   `total_records` bigint unsigned NOT NULL DEFAULT 0,
#   `batch_records` bigint unsigned NOT NULL DEFAULT 0,
#   `max_batch_concurrency` smallint unsigned NOT NULL DEFAULT 5,
#   `current_batch_concurrency` smallint unsigned NOT NULL DEFAULT 0,
#   `max_attempts` tinyint NOT NULL DEFAULT 3,
#   `batch_size` smallint NOT NULL DEFAULT 50,
#   `end_id` bigint unsigned NOT NULL DEFAULT 0,
#   `processor_class` text DEFAULT NULL,
#   `planner_locked_until` bigint unsigned DEFAULT NULL,
#   `planner_token` text DEFAULT NULL,
#   PRIMARY KEY (`id`)
# ) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

  class Import < ActiveRecord::Base
    def self.table_name_prefix
      'massive_import_'
    end
  end

# CREATE TABLE `massive_import_batches` (
#   `id` bigint unsigned NOT NULL AUTO_INCREMENT,
#   `import_id` bigint unsigned NOT NULL,
#   `attempt` tinyint NOT NULL DEFAULT 1,
#   `status` varchar(50) DEFAULT 'PENDING',
#   `start_id` bigint unsigned NOT NULL DEFAULT 0,
#   `end_id` bigint unsigned NOT NULL DEFAULT 0,
#   `started_at` bigint unsigned DEFAULT NULL,
#   `token` text DEFAULT NULL,
#   PRIMARY KEY (`id`),
#   KEY `idx_import_attempt_status` (`import_id`, `attempt`, `status`)
# ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


  class Batch < ActiveRecord::Base
    def self.table_name_prefix
      'massive_import_'
    end
  end

# CREATE TABLE `massive_import_records` (
#   `id` bigint unsigned NOT NULL AUTO_INCREMENT,
#   `import_id` bigint unsigned NOT NULL,
#   `attempt` tinyint NOT NULL DEFAULT 1,
#   `status` varchar(50) DEFAULT 'PENDING',
#   `data` json DEFAULT NULL,
#   PRIMARY KEY (`id`),
#   KEY `idx_import_attempt_status` (`import_id`, `attempt`, `status`)
# ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

  class Record < ActiveRecord::Base
    def self.table_name_prefix
      'massive_import_'
    end
  end

  class << self
    attr_accessor :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset!
      @configuration = Configuration.new
    end

    def stage_records(import, enumerable, **options)
      import.reload
      max_attempts = options.fetch(:max_attempts, import.max_attempts)
      processor_class = options.fetch(:processor_class, import.processor_class)
      batch_size = options.fetch(:batch_size, import.batch_size)
      max_concurrency = options.fetch(:max_batch_concurrency, import.max_batch_concurrency)

      updated = Import
        .where(id: import.id, status: 'PENDING')
        .update_all(
          status: 'STAGING',
          max_attempts: max_attempts,
          processor_class: processor_class.to_s,
          batch_size: batch_size,
          max_batch_concurrency: max_concurrency
        )

      return unless updated > 0

      import.reload
      end_id = import.end_id
      enumerable.each_slice(import.batch_size) do |slice|
        records = slice.map do |record|
          {
            import_id: import.id,
            attempt: import.attempt,
            status: 'PENDING',
            data: record
          }
        end

        committed =
          ActiveRecord::Base.transaction do
            Record.insert_all(records)
            end_id = Record
              .where(import_id: import.id, attempt: import.attempt)
              .order(id: :desc)
              .limit(1)
              .pick(:id)
            raise ActiveRecord::Rollback unless end_id

            updated = Import
              .where(id: import.id, status: 'STAGING')
              .update_all(["total_records = total_records + ?, end_id = ?", records.size, end_id])
            raise ActiveRecord::Rollback unless updated > 0

            true
          end

        return unless committed
      end

      updated = Import
        .where(id: import.id, status: 'STAGING')
        .update_all(status: 'RUNNING', end_id: 0)
      return unless updated > 0

      PlannerJob.set(queue: MassiveImport.configuration.queue_name).perform_async({'import_id' => import.id})
    end
  end

  configuration
end
