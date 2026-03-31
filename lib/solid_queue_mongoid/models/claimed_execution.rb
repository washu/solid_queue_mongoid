# frozen_string_literal: true

module SolidQueue
  class ClaimedExecution < Execution
    assumes_attributes_from_job  # inherits queue_name and priority from job

    field :process_id, type: BSON::ObjectId

    belongs_to :process, class_name: "SolidQueue::Process", optional: true

    # Executions whose process_id references a process that no longer exists.
    scope :orphaned, -> {
      existing_process_ids = SolidQueue::Process.all.pluck(:id)
      where(:process_id.nin => existing_process_ids)
    }

    index({ process_id: 1 })

    class Result < Struct.new(:success, :error)
      def success?
        success
      end
    end

    class << self
      # Atomically creates ClaimedExecution records for the given job_ids and
      # yields the claimed set to the block (which deletes the ReadyExecutions).
      def claiming(job_ids, process_id, &block)
        job_data = Array(job_ids).map { |job_id| { job_id: job_id, process_id: process_id } }

        SolidQueue.instrument(:claim, process_id: process_id, job_ids: job_ids) do |payload|
          claimed = job_data.filter_map do |attrs|
            create!(attrs)
          rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure
            nil
          end

          block.call(claimed)

          payload[:size] = claimed.size
          payload[:claimed_job_ids] = claimed.map(&:job_id)
        end
      end

      def release_all
        SolidQueue.instrument(:release_many_claimed) do |payload|
          executions = all.to_a
          executions.each do |execution|
            begin
              execution.release
            rescue Mongoid::Errors::Validations, Mongo::Error::OperationFailure
              # If ReadyExecution already exists, that's fine
            end
          end
          payload[:size] = executions.size
        end
      end

      def fail_all_with(error)
        executions = includes(:job).to_a
        return if executions.empty?

        SolidQueue.instrument(:fail_many_claimed) do |payload|
          executions.each do |execution|
            execution.failed_with(error)
            execution.unblock_next_job
          end
          payload[:process_ids] = executions.map(&:process_id).uniq
          payload[:job_ids]     = executions.map(&:job_id).uniq
          payload[:size]        = executions.size
        end
      end

      def discard_all_in_batches(*)
        raise UndiscardableError, "Can't discard jobs in progress"
      end

      def discard_all_from_jobs(*)
        raise UndiscardableError, "Can't discard jobs in progress"
      end
    end

    # Called by Pool thread — executes the job and marks it finished or failed.
    def perform
      result = execute

      if result.success?
        finished
      else
        failed_with(result.error)
        raise result.error
      end
    ensure
      unblock_next_job
    end

    # Release this execution back to ready (called by process deregister / prune).
    def release
      SolidQueue.instrument(:release_claimed, job_id: job.id, process_id: process_id) do
        job.dispatch_bypassing_concurrency_limits
        destroy!
      end
    end

    def discard
      raise UndiscardableError, "Can't discard a job in progress"
    end

    def failed_with(error)
      job.failed_with(error)
      destroy!
    end

    def unblock_next_job
      job.unblock_next_blocked_job
    end

    private

      def execute
        ActiveJob::Base.execute(job.arguments.merge("provider_job_id" => job.id.to_s))
        Result.new(true, nil)
      rescue Exception => e
        Result.new(false, e)
      end

      def finished
        job.finished!
        destroy! if persisted?
      end
  end
end
