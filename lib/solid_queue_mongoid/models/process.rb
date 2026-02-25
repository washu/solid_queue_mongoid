# frozen_string_literal: true

module SolidQueue
  class Process < Record
    field :hostname, type: String
    field :pid, type: Integer
    field :name, type: String
    field :metadata, type: Hash
    field :last_heartbeat_at, type: Time

    has_many :claimed_executions, class_name: "SolidQueue::ClaimedExecution", dependent: :destroy

    index({ hostname: 1, pid: 1 })
    index({ last_heartbeat_at: 1 })

    validates :hostname, :pid, presence: true

    def self.register(name:, metadata: {})
      create!(
        hostname: Socket.gethostname,
        pid: ::Process.pid,
        name: name,
        metadata: metadata,
        last_heartbeat_at: Time.current
      )
    end

    def heartbeat
      update!(last_heartbeat_at: Time.current)
    end

    def deregister
      ClaimedExecution.release_all_for_process(self)
      destroy
    end

    def self.prune_stale_processes(timeout: 5.minutes)
      where(:last_heartbeat_at.lt => timeout.ago).destroy_all
    end
  end
end
