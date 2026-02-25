# frozen_string_literal: true

module SolidQueue
  class Job < Record
    include Clearable
    include Recurrable
    include Schedulable
    include Retryable
    include ConcurrencyControls
    include Executable

    field :queue_name, type: String
    field :class_name, type: String
    field :arguments, type: Hash
    field :priority, type: Integer, default: 0

    index({ queue_name: 1 })
    index({ class_name: 1 })
    index({ priority: 1 })
    index({ finished_at: 1 }, { sparse: true })

    validates :queue_name, :class_name, presence: true

    def self.enqueue(active_job, scheduled_at: nil)
      job = create!(
        active_job_id: active_job.job_id,
        queue_name: active_job.queue_name,
        class_name: active_job.class.name,
        arguments: active_job.serialize,
        priority: active_job.priority || 0,
        scheduled_at: scheduled_at
      )

      job.dispatch
      job
    end

    def deserialize_for_active_job
      ActiveJob::Base.deserialize(arguments)
    end
  end
end
