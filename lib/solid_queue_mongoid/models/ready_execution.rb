# frozen_string_literal: true

module SolidQueue
  class ReadyExecution < Execution
    def self.claim_batch(batch_size, process:, queues: "*")
      queue_names = resolve_queue_names(queues)

      claimed = []
      batch_size.times do
        # Use MongoDB's findOneAndDelete for atomic claim
        # Sort by priority DESC (higher priority first), then created_at ASC (older first)
        result = collection.find_one_and_delete(
          { "queue_name" => { "$in" => queue_names } },
          sort: { "priority" => -1, "created_at" => 1 }
        )

        break unless result

        # Create claimed execution for this job
        begin
          job = Job.find(result["job_id"])
          claimed_execution = ClaimedExecution.create!(
            job: job,
            process: process,
            queue_name: result["queue_name"],
            priority: result["priority"]
          )
          claimed << claimed_execution
        rescue => e
          # If claimed execution creation fails, log error but continue
          # The ready execution is already deleted, so we can't re-add it
          Rails.logger.error("Failed to create claimed execution: #{e.message}") if defined?(Rails)
        end
      end

      claimed
    end
  end
end
