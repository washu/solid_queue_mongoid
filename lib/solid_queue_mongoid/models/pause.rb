# frozen_string_literal: true

module SolidQueue
  class Pause < Record
    field :queue_name, type: String

    index({ queue_name: 1 }, { unique: true })

    validates :queue_name, presence: true, uniqueness: true

    def self.pause_queue(queue_name)
      find_or_create_by(queue_name: queue_name)
    end

    def self.resume_queue(queue_name)
      where(queue_name: queue_name).first&.destroy
    end

    def self.paused?(queue_name)
      exists?(queue_name: queue_name)
    end
  end
end
