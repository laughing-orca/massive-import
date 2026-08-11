require 'securerandom'

module MassiveImport
  class ProcessorJob
    include Sidekiq::Job
    sidekiq_options retry: false

    VALID_RECORD_STATUSES = ['COMPLETED', 'INVALID']

    def perform(args)
      batch_claimed = false
      import_id = args['import_id']
      return unless import_id

      import = Import.find_by(id: import_id, status: 'RUNNING')
      return unless import

      token = SecureRandom.hex
      batch = claim_batch(import, token)
      return unless batch

      batch_claimed = true
      process_batch(import, batch, token)
    rescue
      decrement_current_concurrency(import_id) unless batch_claimed
      raise
    end

    def claim_batch(import, token)
      ActiveRecord::Base.transaction do
        batch = Batch
          .lock("FOR UPDATE SKIP LOCKED")
          .find_by(import_id: import.id, status: 'PENDING', attempt: import.attempt)

        if batch
          batch.update_columns(status: 'RUNNING', started_at: Time.current.to_i, token: token)
          batch
        else
          decrement_current_concurrency(import.id)
          nil
        end
      end
    end

    def decrement_current_concurrency(import_id)
      Import
        .where(id: import_id)
        .where("current_batch_concurrency > 0")
        .update_all("current_batch_concurrency = GREATEST(0, current_batch_concurrency - 1)")
    end

    def process_batch(import, batch, token)
      processor_instance = (import.processor_class.constantize.new rescue nil)

      Record.where(import_id: import.id, attempt: import.attempt, status: 'PENDING', id: (batch.start_id..batch.end_id))
            .find_in_batches(batch_size: 50) do |slice|
        
        updated = Batch.where(id: batch.id, status: 'RUNNING', token: token).update_all(started_at: Time.current.to_i)
        return unless updated > 0

        records_by_status = Hash.new { |h, k| h[k] = [] }

        slice.each do |record|
          status = process_record(processor_instance, record)
          records_by_status[status] << record.id
        end

        update_record_statuses(import, records_by_status)
      end

      ActiveRecord::Base.transaction do
        updated = Batch
          .where(id: batch.id, status: 'RUNNING', token: token)
          .update_all(status: 'COMPLETED')
        raise ActiveRecord::Rollback unless updated > 0
        decrement_current_concurrency(import.id)
      end
    end

    def process_record(processor_instance, record)
      return 'INVALID' unless processor_instance && processor_instance.respond_to?(:process)
      status = processor_instance.process(record.data)
      VALID_RECORD_STATUSES.include?(status) ? status : 'RETRY'
    rescue
      'RETRY'
    end

    def update_record_statuses(import, records_by_status)
      records_by_status.each do |record_status, ids|
        if record_status == 'RETRY'
          Record.where(import_id: import.id, attempt: import.attempt, id: ids)
                .update_all("status = 'PENDING', attempt = attempt + 1")
        else
          Record.where(import_id: import.id, attempt: import.attempt, id: ids)
                .update_all(status: record_status)
        end
      end
    end
  end
end


