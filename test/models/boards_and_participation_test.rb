# frozen_string_literal: true

require 'test_helper'

module Ideasbugs
  class BoardsAndParticipationTest < ActiveSupport::TestCase
    def feedback(**attributes)
      Feedback.create!({ message: 'A useful feature', kind: 'feature', visibility: 'listed' }.merge(attributes))
    end

    test 'default boards isolate opaque tenants and cannot be deleted' do
      global = Board.default_for(nil)
      assert_equal global, Board.default_for(nil)
      assert_not_equal global, Board.default_for('acme')
      assert_equal 'private', global.visibility
      assert_not global.destroy
      assert_not Feedback.new(message: 'No', kind: 'bug', tenant: 'other', board: global).valid?
    end

    test 'votes are idempotent and require visible feedback' do
      item = feedback
      action = Participation.new(item)
      2.times { action.vote(actor_id: 'abc', label: 'Member') }
      assert_equal 1, item.reload.votes_count
      2.times { action.vote(actor_id: 'abc', label: 'Member', remove: true) }
      assert_equal 0, item.reload.votes_count
      item.update!(visibility: 'unlisted')
      assert_raises(ActiveRecord::RecordInvalid) { action.vote(actor_id: 'abc', label: 'Member') }
    end

    test 'comment replies stay one level and on the same feedback' do
      item = feedback
      action = Participation.new(item)
      parent = action.comment(actor_id: 'a', label: 'Member', body: 'First')
      reply = action.comment(actor_id: 'b', label: 'Other', body: 'Reply', parent_id: parent.id)
      assert_equal 2, item.reload.comments_count
      assert_raises(ActiveRecord::RecordInvalid) do
        action.comment(actor_id: 'a', label: 'Member', body: 'Too deep', parent_id: reply.id)
      end
      assert_raises(ActiveRecord::RecordNotFound) do
        Participation.new(feedback).comment(actor_id: 'a', label: 'Member', body: 'Wrong item', parent_id: parent.id)
      end
      action.delete_comment(parent.id)
      assert_equal 0, item.reload.comments_count
    end

    test 'merges deduplicate voters preserve comments and flatten chains' do
      source = feedback
      target = feedback
      [source, target].each { |item| Participation.new(item).vote(actor_id: 'same', label: 'Member') }
      Participation.new(source).vote(actor_id: 'unique', label: 'Other')
      Participation.new(source).comment(actor_id: 'same', label: 'Member', body: 'Keep this')
      Merge.call(source: source, target: target)
      assert_equal 2, target.reload.votes_count
      assert_equal 0, source.reload.votes_count
      assert_equal 1, source.comments.count
      assert_equal 'merged', source.visibility
      assert_raises(ActiveRecord::RecordInvalid) { Participation.new(source).vote(actor_id: 'late', label: 'Member') }
      canonical = feedback
      Merge.call(source: target, target: canonical)
      assert_equal canonical, source.reload.merged_into
      assert_not canonical.destroy
    end

    test 'merge blocks crossing tenants or privacy boundaries' do
      source = feedback
      other = feedback(tenant: 'other')
      assert_raises(ArgumentError) { Merge.call(source: source, target: other) }
      public_board = Board.create!(name: 'Public', visibility: 'public')
      target = feedback(board: public_board)
      assert_raises(ArgumentError) { Merge.call(source: source, target: target) }
    end
  end
end
