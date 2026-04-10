# frozen_string_literal: true

module SolidQueue
  # Mirrors SolidQueue::QueueSelector but uses Mongo queries for wildcard resolution.
  class QueueSelector
    attr_reader :raw_queues, :relation

    def initialize(queue_list, relation)
      @raw_queues = Array(queue_list).map { |q| q.to_s.strip }.presence || ["*"]
      @relation = relation
    end

    # Returns an array of Mongoid criteria scoped to individual queue names,
    # or a single all/none criteria when appropriate.
    def scoped_relations
      if all?
        [relation.all]
      elsif none?
        []
      else
        queue_names.map { |queue_name| relation.queued_as(queue_name) }
      end
    end

    private

    def all?
      include_all_queues? && paused_queues.empty?
    end

    def none?
      queue_names.empty?
    end

    def queue_names
      @queue_names ||= eligible_queues - paused_queues
    end

    def eligible_queues
      if include_all_queues?
        all_queues
      else
        in_raw_order(exact_names + prefixed_names)
      end
    end

    def include_all_queues?
      raw_queues.include?("*")
    end

    # Pull all distinct queue names currently present in this relation.
    def all_queues
      relation.distinct(:queue_name)
    end

    def exact_names
      raw_queues.select { |q| exact_name?(q) }
    end

    def prefixed_names
      return [] if prefixes.empty?

      prefixes.flat_map do |prefix|
        # Use anchored regex for mongo prefix match
        relation.where(queue_name: /\A#{Regexp.escape(prefix)}/).distinct(:queue_name)
      end.uniq
    end

    def prefixes
      @prefixes ||= raw_queues.select { |q| prefixed_name?(q) }.map { |q| q.chomp("*") }
    end

    def exact_name?(queue)
      !queue.include?("*")
    end

    def prefixed_name?(queue)
      queue.end_with?("*")
    end

    def paused_queues
      @paused_queues ||= Pause.all.pluck(:queue_name)
    end

    def in_raw_order(queues)
      return queues if queues.size <= 1 || prefixes.empty?

      queues = queues.dup
      raw_queues.flat_map { |raw| delete_in_order(raw, queues) }.compact
    end

    def delete_in_order(raw_queue, queues)
      if exact_name?(raw_queue)
        queues.delete(raw_queue)
      elsif prefixed_name?(raw_queue)
        prefix = raw_queue.chomp("*")
        queues.select { |q| q.start_with?(prefix) }.tap { |matches| queues -= matches }
      end
    end
  end
end
