# frozen_string_literal: true

module SolidQueue
  class RecurringExecution < Record
    class AlreadyRecorded < StandardError; end

    field :task_key, type: String
    field :run_at,   type: Time

    # optional: job may have been purged already
    belongs_to :job, class_name: "SolidQueue::Job", optional: true

    index({ task_key: 1, run_at: 1 }, { unique: true })
    index({ job_id: 1 })

    # Clearable when the associated job no longer exists.
    scope :clearable, -> {
      existing_job_ids = SolidQueue::Job.all.pluck(:id)
      where(:job_id.nin => existing_job_ids).or(job_id: nil)
    }

    class << self
      # Called by RecurringTask#enqueue_and_record.
      # Wraps the block; records the execution only if the job was successfully enqueued.
      def record(task_key, run_at, &block)
        active_job = block.call

        if active_job && active_job.successfully_enqueued?
          create_or_insert!(
            task_key: task_key,
            run_at:   run_at,
            job_id:   active_job.provider_job_id
          )
        end

        active_job
      end

      # Atomic insert — raises AlreadyRecorded on duplicate (same task_key + run_at).
      def create_or_insert!(task_key:, run_at:, job_id: nil)
        create!(task_key: task_key, run_at: run_at, job_id: job_id)
      rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure => e
        raise AlreadyRecorded if duplicate_key_error?(e)
        raise
      end

      def clear_in_batches(batch_size: 500)
        loop do
          deleted = clearable.limit(batch_size).delete_all
          break if deleted == 0
        end
      end

      private

        def duplicate_key_error?(err)
          err.message.to_s.include?("E11000") || err.message.to_s.include?("duplicate key")
        end
    end
  end
end
