# frozen_string_literal: true

module SolidQueue
  # Plain Ruby class — mirrors upstream SolidQueue::Queue (1.3.x).
  # State is derived from actual Job/Pause/ReadyExecution documents;
  # no separate Queue collection is maintained.
  class Queue
    attr_accessor :name

    class << self
      def all
        Job.distinct(:queue_name).map { |queue_name| new(queue_name) }
      end

      def find_by_name(name)
        new(name)
      end
    end

    def initialize(name)
      @name = name
    end

    def paused?
      Pause.where(queue_name: name).exists?
    end

    def pause
      Pause.pause_queue(name)
    end

    def resume
      Pause.resume_queue(name)
    end

    def clear
      ReadyExecution.queued_as(name).discard_all_in_batches
    end

    def size
      @size ||= ReadyExecution.queued_as(name).count
    end

    def latency
      @latency ||= begin
        now = Time.current
        oldest_enqueued_at = ReadyExecution.queued_as(name).min(:created_at) || now
        (now - oldest_enqueued_at).to_i
      end
    end

    def human_latency
      ActiveSupport::Duration.build(latency).inspect
    end

    def ==(other)
      name == (other.respond_to?(:name) ? other.name : other)
    end
    alias eql? ==

    def hash
      name.hash
    end
  end
end
