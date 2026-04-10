# frozen_string_literal: true

module SolidQueue
  class Job < Record
    class EnqueueError < StandardError; end

    include Clearable
    include Recurrable
    include Executable # includes ConcurrencyControls, Schedulable, Retryable

    field :queue_name, type: String
    field :class_name, type: String
    field :arguments, type: Hash, default: {}
    field :priority, type: Integer, default: 0
    field :active_job_id, type: String
    field :concurrency_key, type: String
    field :concurrency_limit, type: Integer # stored per-job; overrides job_class.concurrency_limit
    field :finished_at, type: Time
    field :max_retries, type: Integer, default: 0
    field :retry_count, type: Integer, default: 0

    index({ queue_name: 1 })
    index({ class_name: 1 })
    index({ priority: 1 })
    index({ active_job_id: 1 }, { sparse: true })
    index({ finished_at: 1 }, { sparse: true })
    index({ concurrency_key: 1 }, { sparse: true })

    validates :queue_name, :class_name, presence: true

    DEFAULT_PRIORITY = 0
    DEFAULT_QUEUE_NAME = "default"

    class << self
      # Primary enqueue entry point — called by the ActiveJob adapter.
      def enqueue(active_job, scheduled_at: Time.current)
        active_job.scheduled_at = scheduled_at

        create_from_active_job(active_job).tap do |enqueued_job|
          if enqueued_job.persisted?
            active_job.provider_job_id = enqueued_job.id.to_s
            active_job.successfully_enqueued = true
          end
        end
      end

      # Bulk enqueue — called by the ActiveJob adapter for perform_all_later.
      def enqueue_all(active_jobs)
        active_jobs.each { |job| job.scheduled_at = Time.current }
        active_jobs_by_job_id = active_jobs.index_by(&:job_id)

        jobs = create_all_from_active_jobs(active_jobs)

        prepare_all_for_execution(jobs).tap do |enqueued_jobs|
          enqueued_jobs.each do |enqueued_job|
            aj = active_jobs_by_job_id[enqueued_job.active_job_id]
            next unless aj

            aj.provider_job_id = enqueued_job.id.to_s
            aj.successfully_enqueued = true
          end
        end

        active_jobs.count(&:successfully_enqueued?)
      end

      private

      def create_from_active_job(active_job)
        create!(**attributes_from_active_job(active_job))
      rescue StandardError => e
        enqueue_error = EnqueueError.new("#{e.class.name}: #{e.message}").tap do |err|
          err.set_backtrace(e.backtrace)
        end
        raise enqueue_error
      end

      def create_all_from_active_jobs(active_jobs)
        active_jobs.filter_map do |active_job|
          create_from_active_job(active_job)
        rescue EnqueueError
          nil
        end
      end

      def attributes_from_active_job(active_job)
        {
          queue_name: active_job.queue_name || DEFAULT_QUEUE_NAME,
          active_job_id: active_job.job_id,
          priority: active_job.priority || DEFAULT_PRIORITY,
          scheduled_at: active_job.scheduled_at,
          class_name: active_job.class.name,
          arguments: active_job.serialize,
          concurrency_key: active_job.try(:concurrency_key)
        }.compact
      end
    end

    def deserialize_for_active_job
      ActiveJob::Base.deserialize(arguments)
    end
  end
end
