# frozen_string_literal: true

module Ideasbugs
  class Merge
    def self.call(source:, target:)
      Feedback.transaction do
        # All writers lock these same rows. Stable ordering avoids opposing merges.
        records = Feedback.where(id: [source.id, target.id]).order(:id).lock.to_a
        source = records.find { |record| record.id == source.id }
        target = records.find { |record| record.id == target.id }
        unless source && target && source != target && source.tenant == target.tenant &&
               source.visibility == 'listed' && target.visibility == 'listed' &&
               source.board.visibility == target.board.visibility
          raise ArgumentError, 'Merge requires distinct listed items in the same tenant with matching board visibility'
        end

        source.votes.find_each do |vote|
          next if target.votes.exists?(voter_id: vote.voter_id)

          target.votes.create!(voter_id: vote.voter_id, voter_label: vote.voter_label, created_at: vote.created_at,
                               updated_at: vote.updated_at)
        end
        source.votes.delete_all
        source.merged_sources.update_all(merged_into_id: target.id)
        source.update!(visibility: 'merged', merged_into: target, votes_count: 0)
        target.update!(votes_count: target.votes.count)
        target
      end
    end
  end
end
