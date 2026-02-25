# frozen_string_literal: true

module SolidQueue
  class Queue < Record
    field :name, type: String
    field :paused, type: Boolean, default: false

    index({ name: 1 }, { unique: true })

    validates :name, presence: true, uniqueness: true

    def self.find_or_create_by_name(name)
      find_or_create_by(name: name)
    end

    def pause
      update(paused: true)
    end

    def resume
      update(paused: false)
    end

    def paused?
      paused
    end
  end
end
