# frozen_string_literal: true

module SolidQueue
  # Queue is a Mongoid-backed model storing queue name and paused state.
  # In solid_queue 1.3.x (AR) it is a plain Ruby class, but our specs
  # treat it as a persisted model, so we make it a Record subclass.
  class Queue < Record
    field :name,   type: String
    field :paused, type: Boolean, default: false

    index({ name: 1 }, { unique: true })

    validates :name, presence: true, uniqueness: true

    class << self
      def find_or_create_by_name(name)
        create_or_find_by!(name: name)
      end

      def find_by_name(name)
        where(name: name).first
      end

      def all_queues
        all.map(&:name)
      end
    end

    def pause
      update!(paused: true)
      Pause.pause_queue(name)
      self
    end

    def resume
      update!(paused: false)
      Pause.resume_queue(name)
      self
    end

    def paused?
      paused == true
    end

    def size
      ReadyExecution.queued_as(name).count
    end

    def latency
      now = Time.current
      oldest = ReadyExecution.queued_as(name).order_by(created_at: :asc).first&.created_at || now
      (now - oldest).to_i
    end

    def human_latency
      ActiveSupport::Duration.build(latency).inspect
    end

    def clear
      ReadyExecution.queued_as(name).discard_all_in_batches
    end

    def ==(other)
      name == (other.respond_to?(:name) ? other.name : other)
    end
    alias_method :eql?, :==

    def hash
      name.hash
    end
  end
end
