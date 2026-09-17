# frozen_string_literal: true

module Ideasbugs
  # Row locking serializes participation with moderation and merging. Callers
  # must first resolve the record through an authorized tenant/board scope.
  class Participation
    def initialize(feedback)
      @feedback = feedback
    end

    def vote(actor_id:, label:, remove: false)
      @feedback.with_lock do
        require_listed!
        existing = @feedback.votes.find_by(voter_id: actor_id.to_s)
        if remove
          existing&.destroy!
        elsif !existing
          @feedback.votes.create!(voter_id: actor_id.to_s, voter_label: label)
        end
        @feedback.update!(votes_count: @feedback.votes.count)
      end
    end

    def comment(actor_id:, label:, body:, parent_id: nil, admin: false)
      @feedback.with_lock do
        require_listed!
        parent = @feedback.comments.find(parent_id) if parent_id.present?
        comment = @feedback.comments.create!(author_id: actor_id.to_s, author_label: label, body: body, parent: parent,
                                             admin: admin)
        @feedback.update!(comments_count: @feedback.comments.count)
        comment
      end
    end

    def delete_comment(comment_id)
      @feedback.with_lock do
        @feedback.comments.find(comment_id).destroy!
        @feedback.update!(comments_count: @feedback.comments.count)
      end
    end

    private

    def require_listed!
      return if @feedback.visibility == 'listed'

      @feedback.errors.add(:base, 'Only listed feedback accepts votes and comments')
      raise ActiveRecord::RecordInvalid, @feedback
    end
  end
end
