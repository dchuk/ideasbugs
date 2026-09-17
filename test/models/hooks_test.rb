# frozen_string_literal: true

require 'test_helper'

class HooksTest < ActiveSupport::TestCase
  test 'status hook sees actual changes and ignores no-op updates' do
    calls = []
    Ideasbugs.config.on_status_change = ->(item, previous) { calls << [item.status, previous] }
    feedback = Ideasbugs::Feedback.create!(kind: 'feature', message: 'Request')
    feedback.update!(status: 'planned')
    feedback.update!(status: 'planned')
    assert_equal [%w[planned under_review]], calls
  end

  test 'rollback does not run comment or submission hooks' do
    calls = []
    Ideasbugs.config.on_submit = ->(item) { calls << item }
    Ideasbugs.config.on_comment = ->(comment) { calls << comment }
    Ideasbugs::Feedback.transaction(requires_new: true) do
      feedback = Ideasbugs::Feedback.create!(kind: 'feature', message: 'Request', visibility: 'listed')
      Ideasbugs::Participation.new(feedback).comment(actor_id: 'a', label: 'Member', body: 'Reply')
      raise ActiveRecord::Rollback
    end
    assert_empty calls
  end

  test 'hook failure does not roll back committed discussion' do
    feedback = Ideasbugs::Feedback.create!(kind: 'feature', message: 'Request', visibility: 'listed')
    Ideasbugs.config.on_comment = ->(_comment) { raise 'External hook unavailable' }
    Ideasbugs::Participation.new(feedback).comment(actor_id: 'a', label: 'Member', body: 'Keep this')
    assert_equal 1, feedback.reload.comments_count
  end
end
