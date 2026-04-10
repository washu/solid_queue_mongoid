# frozen_string_literal: true

module SolidQueue
  class Process
    module Prunable
      extend ActiveSupport::Concern

      included do
        # Processes whose heartbeat is older than the alive threshold
        scope :prunable, lambda {
          where(:last_heartbeat_at.lte => SolidQueue.process_alive_threshold.ago)
        }
      end

      class_methods do
        # Called by supervisor maintenance loop.
        # +excluding+ is the current supervisor Process record (or nil).
        def prune(excluding: nil)
          SolidQueue.instrument(:prune_processes, size: 0) do |payload|
            scope = prunable
            scope = scope.not.where(id: excluding.id) if excluding.present?

            scope.each do |process|
              payload[:size] += 1
              process.prune
            end
          end
        end

        # Integration-spec compatible helper: prune processes whose heartbeat
        # is older than +timeout+ ago.
        def prune_stale_processes(timeout: SolidQueue.process_alive_threshold)
          where(:last_heartbeat_at.lte => timeout.ago).each(&:prune)
        end
      end

      def prune
        error = begin
          ::SolidQueue::Processes::ProcessPrunedError.new(last_heartbeat_at)
        rescue NameError
          RuntimeError.new("Process pruned: last heartbeat at #{last_heartbeat_at}")
        end

        fail_all_claimed_executions_with(error)
        deregister(pruned: true)
      end
    end
  end
end
