require 'securerandom'

module MassiveImport
  class PlannerJob
    include Sidekiq::Job
    sidekiq_retry_in do |count, exception, jobhash|
      MassiveImport.configuration.planning_interval + rand(1..10)
    end

    def perform(args)
      import_id = args['import_id']
      return unless import_id

      import = Import.find_by(id: import_id, status: 'RUNNING')
      return unless import

      token = SecureRandom.hex
      lock_acquired = acquire_planner_lock(import, token)
      return unless lock_acquired

      if import.total_records == 0
        import.update_columns(status: 'COMPLETED')
        return
      end

      recover_timedout_batches(import)

      batch_stats = Batch.where(import_id: import.id, attempt: import.attempt).group(:status).count
      pending_batches = batch_stats.fetch('PENDING', 0)
      running_batches = batch_stats.fetch('RUNNING', 0)
      batches_created = 0

      if pending_batches * 2 <= import.max_batch_concurrency
        batches_created = create_batches(import, token)
        return if batches_created < 0

        if batches_created == 0 && pending_batches == 0 && running_batches == 0
          import.reload
          done = handle_attempt_completion(import, token)
          return if done
        end
      end

      import.reload
      dispatch_workers(import, import.max_batch_concurrency, token)
      enqueue_self(import)
    ensure
      release_planner_lock(import, token) if lock_acquired
    end

    private

    def acquire_planner_lock(import, token)
      now = Time.current.to_i
      lease = MassiveImport.configuration.planner_lease

      Import
        .where(id: import.id, status: 'RUNNING')
        .where("planner_locked_until IS NULL OR planner_locked_until < ?", now)
        .update_all(planner_locked_until: now + lease, planner_token: token) > 0
    end

    def release_planner_lock(import, token)
      Import
        .where(id: import.id, planner_token: token)
        .update_all(planner_locked_until: nil, planner_token: nil)
    end

    def recover_timedout_batches(import)
      updated = Batch
        .where(import_id: import.id, attempt: import.attempt, status: 'RUNNING')
        .where('started_at < ?', Time.current.to_i - MassiveImport.configuration.batch_timeout)
        .update_all(status: 'PENDING', started_at: nil)

      if updated > 0
        Import.where(id: import.id)
              .where("current_batch_concurrency > 0")
              .update_all(["current_batch_concurrency = GREATEST(0, current_batch_concurrency - ?)", updated])
        import.reload
      end
    end

    def dispatch_workers(import, requested_count, token)
      slots_available = import.max_batch_concurrency - import.current_batch_concurrency
      workers_to_enqueue = [requested_count, slots_available].min

      workers_to_enqueue.times do
        enqueue_processor(import, token)
      end
    end

    def enqueue_processor(import, token)
      updated = Import
        .where(id: import.id, status: 'RUNNING', planner_token: token)
        .where("current_batch_concurrency < max_batch_concurrency")
        .update_all("current_batch_concurrency = current_batch_concurrency + 1")

      if updated > 0
        ProcessorJob
          .set(queue: MassiveImport.configuration.queue_name)
          .perform_async({ 'import_id' => import.id })
      end
    end

    def enqueue_self(import)
      self.class.set(queue: MassiveImport.configuration.queue_name)
        .perform_in(MassiveImport.configuration.planning_interval, { 'import_id' => import.id })
    end

    def create_batches(import, token)
      return 0 if (import.batch_records >= import.total_records)

      batch_size = import.batch_size
      end_id = import.end_id
      new_batches = []
      new_batch_records = 0
      import.max_batch_concurrency.times do
        records = Record
                    .where(import_id: import.id, attempt: import.attempt, status: 'PENDING')
                    .where("id > ?", end_id)
                    .order(:id)
                    .limit(batch_size)
                    .pluck(:id)

        break if records.empty?

        end_id = records[-1]
        new_batch_records += records.size

        new_batches << {
          import_id: import.id,
          attempt: import.attempt,
          status: 'PENDING',
          start_id: records[0],
          end_id: end_id
        }
      end
      return 0 if new_batches.empty?

      committed =
        ActiveRecord::Base.transaction do
          updated = Import
            .where(id: import.id, status: 'RUNNING', planner_token: token)
            .update_all(["end_id = ?, batch_records = batch_records + ?", end_id, new_batch_records])

          raise ActiveRecord::Rollback unless updated > 0

          Batch.insert_all(new_batches)
        end

      return -1 unless committed
      new_batches.size
    end

    def handle_attempt_completion(import, token)
      batch_records = import.batch_records
      total_records = import.total_records
      return false if batch_records < total_records

      retry_count = Record.where(import_id: import.id, attempt: import.attempt + 1, status: 'PENDING').count
      if retry_count == 0 || import.attempt >= import.max_attempts
        updated = Import
          .where(id: import.id, status: 'RUNNING', planner_token: token)
          .update_all(status: 'COMPLETED')
        return updated > 0
      end

      updated = Import
        .where(id: import.id, status: 'RUNNING', planner_token: token)
        .update_all(["attempt = attempt + 1, end_id = 0, batch_records = 0, total_records = ?", retry_count])
      return false unless updated > 0

      enqueue_self(import)
      true
    end
  end
end
