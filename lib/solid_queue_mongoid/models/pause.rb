# frozen_string_literal: true

module SolidQueue
  class Pause < Record
    field :queue_name, type: String

    index({ queue_name: 1 }, { unique: true })

    validates :queue_name, presence: true, uniqueness: true

    class << self
      def pause_queue(queue_name)
        create_or_find_by!(queue_name: queue_name)
      end

      def resume_queue(queue_name)
        where(queue_name: queue_name).delete_all
      end

      def paused?(queue_name)
        where(queue_name: queue_name).exists?
      end
    end
  end
end
