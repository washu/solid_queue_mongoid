# frozen_string_literal: true

module SolidQueue
  class Semaphore < Record
    field :key, type: String
    field :value, type: Integer, default: 0
    field :limit, type: Integer

    index({ key: 1 }, { unique: true })

    validates :key, presence: true, uniqueness: true

    def acquire
      result = collection.find_one_and_update(
        { _id: id, "value" => { "$lt" => limit } },
        { "$inc" => { "value" => 1 } },
        return_document: :after
      )

      result.present?
    end

    def release
      collection.find_one_and_update(
        { _id: id, "value" => { "$gt" => 0 } },
        { "$inc" => { "value" => -1 } },
        return_document: :after
      )
    end

    def available?
      reload
      value < limit
    end
  end
end
