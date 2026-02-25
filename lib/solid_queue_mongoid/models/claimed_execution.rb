# frozen_string_literal: true

module SolidQueue
  class ClaimedExecution < Execution
    field :process_id, type: BSON::ObjectId

    belongs_to :process, class_name: "SolidQueue::Process", optional: false

    index({ process_id: 1 })

    def release
      destroy
      job.create_ready_execution!
    end

    def self.release_all_for_process(process)
      where(process: process).each(&:release)
    end
  end
end
