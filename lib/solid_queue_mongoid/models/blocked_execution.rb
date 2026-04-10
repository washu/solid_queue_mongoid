# frozen_string_literal: true

module SolidQueue
  class BlockedExecution < Execution
    assumes_attributes_from_job :concurrency_key

    field :concurrency_key, type: String
    field :expires_at, type: Time

    before_create :set_expires_at

    index({ concurrency_key: 1, created_at: 1 })
    index({ expires_at: 1 })

    scope :expired, -> { where(:expires_at.lt => Time.current) }

    class << self
      # Make create! idempotent: if a BlockedExecution for this job already exists
      # (e.g. created by auto-dispatch), return the existing record instead of raising.
      def create!(**attrs, &block)
        super
      rescue Mongo::Error::OperationFailure => e
        raise unless e.message.to_s.include?("E11000") || e.message.to_s.include?("duplicate key")
        job_id = attrs[:job_id] || (attrs[:job]&.id)
        where(job_id: job_id).first || raise(e)
      rescue Mongoid::Errors::Validations => e
        return where(job_id: attrs[:job_id] || attrs[:job]&.id).first || raise(e) if uniqueness_only_error?(e.document)
        raise
      end

      def unblock(limit)
        SolidQueue.instrument(:release_many_blocked, limit: limit) do |payload|
          expired_keys = expired.order(:concurrency_key).distinct(:concurrency_key).first(limit)
          payload[:size] = release_many(releasable(expired_keys))
        end
      end

      # Convenience method: release blocked executions for a given concurrency key.
      # +limit+ is the maximum number to unblock (default: all).
      def unblock_all(concurrency_key, limit = nil)
        scope = ordered.where(concurrency_key: concurrency_key)
        scope = scope.limit(limit) if limit
        count = 0
        scope.each do |execution|
          break if limit && count >= limit
          count += 1 if execution.release
        end
        count
      end

      def release_many(concurrency_keys)
        Array(concurrency_keys).count { |key| release_one(key) }
      end

      def release_one(concurrency_key)
        Mongoid.transaction do
          execution = ordered.where(concurrency_key: concurrency_key).limit(1).first
          execution ? execution.release : false
        end
      end

      private

      def releasable(concurrency_keys)
        semaphores = Semaphore.where(:key.in => concurrency_keys).pluck(:key, :value, :limit)
        # Build hash of key => [value, limit]
        sem_map = semaphores.each_with_object({}) do |(key, value, limit), h|
          h[key] = { value: value, limit: limit }
        end

        # Keys without semaphore (never acquired) + keys where value < limit (slot available)
        (concurrency_keys - sem_map.keys) +
          sem_map.select { |_key, s| s[:value] < s[:limit] }.keys
      end
    end

    def unblock
      release
    end

    def release
      SolidQueue.instrument(:release_blocked, job_id: job.id, concurrency_key: concurrency_key, released: false) do |payload|
        Mongoid.transaction do
          if acquire_concurrency_lock
            promote_to_ready
            destroy!
            payload[:released] = true
            true
          else
            false
          end
        end
      end
    end

    private

    def set_expires_at
      self.expires_at = job.concurrency_duration.from_now
    end

    def acquire_concurrency_lock
      Semaphore.wait(job)
    end

    def promote_to_ready
      existing = ReadyExecution.where(job_id: job_id).first
      return existing if existing

      ReadyExecution.create!(job_id: job_id, queue_name: queue_name, priority: priority)
    rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure
      ReadyExecution.where(job_id: job_id).first
    end
  end
end
