# frozen_string_literal: true

module SolidQueue
  class Process < Record
    include Process::Executor
    include Process::Prunable

    field :kind, type: String
    field :name, type: String
    field :hostname, type: String
    field :pid, type: Integer
    field :supervisor_id, type: BSON::ObjectId
    field :metadata, type: Hash, default: {}
    field :last_heartbeat_at, type: Time

    belongs_to :supervisor, class_name: "SolidQueue::Process", optional: true,
                            inverse_of: :supervisees
    has_many :supervisees, class_name: "SolidQueue::Process",
                           inverse_of: :supervisor, foreign_key: :supervisor_id

    index({ hostname: 1, pid: 1 })
    index({ last_heartbeat_at: 1 })
    index({ kind: 1 })
    index({ supervisor_id: 1 }, { sparse: true })

    validates :hostname, :pid, presence: true

    class << self
      # Called by SolidQueue::Processes::Registrable#register.
      # Must accept: kind:, name:, pid:, hostname:, and optional metadata:/supervisor:
      def register(kind:, name:, pid:, hostname:, supervisor: nil, metadata: {}, **rest)
        attrs = { kind: kind, name: name, pid: pid, hostname: hostname,
                  supervisor: supervisor, metadata: (metadata || {}).merge(rest),
                  last_heartbeat_at: Time.current }
        SolidQueue.instrument(:register_process, kind: kind, name: name, pid: pid, hostname: hostname) do |payload|
          create!(attrs).tap do |process|
            payload[:process_id] = process.id
          end
        rescue StandardError => e
          payload[:error] = e
          raise
        end
      end
    end

    def heartbeat
      # Reload to clear any stale state before updating heartbeat
      begin
        reload
      rescue StandardError
        nil
      end
      update!(last_heartbeat_at: Time.current)
    end

    def deregister(pruned: false)
      SolidQueue.instrument(:deregister_process, process: self, pruned: pruned) do |payload|
        destroy!

        supervisees.each(&:deregister) unless supervised? || pruned
      rescue StandardError => e
        payload[:error] = e
        raise
      end
    end

    private

    def supervised?
      supervisor_id.present?
    end
  end
end
