# frozen_string_literal: true

unless ENV['DATABASE_URL'].to_s.include?('ideasbugs_test')
  raise 'Set DATABASE_URL to a disposable ideasbugs_test database'
end

require 'test_helper'

class ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    Ideasbugs::Feedback.update_all(merged_into_id: nil)
    Ideasbugs::Feedback.destroy_all
  end

  def item
    Ideasbugs::Feedback.create!(message: 'Concurrent request', kind: 'feature', visibility: 'listed')
  end

  def concurrently(*operations)
    ready = Queue.new
    start = Queue.new
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          operation.call
        end
      end
    end
    operations.size.times { ready.pop }
    operations.size.times { start << true }
    threads.each(&:value)
  end

  test 'concurrent repeated votes retain one row and one cached vote' do
    feedback = item
    operation = lambda do
      Ideasbugs::Participation.new(Ideasbugs::Feedback.find(feedback.id)).vote(actor_id: 'same', label: 'Member')
    end
    concurrently(operation, operation)
    assert_equal 1, feedback.reload.votes_count
    assert_equal 1, feedback.votes.count
  end

  test 'a vote racing a merge is transferred or rejected without count loss' do
    source = item
    target = item
    concurrently(
      -> { Ideasbugs::Merge.call(source: source, target: target) },
      lambda do
        Ideasbugs::Participation.new(Ideasbugs::Feedback.find(source.id)).vote(actor_id: 'new', label: 'Member')
      rescue ActiveRecord::RecordInvalid
        # The merge got the lock first: the old request is now read-only.
      end
    )
    assert_equal 0, source.reload.votes_count
    assert_equal target.votes.count, target.reload.votes_count
    assert_includes [0, 1], target.votes_count
  end

  test 'opposing concurrent merges leave a single canonical request without a cycle' do
    first = item
    second = item
    merge = lambda do |source, target|
      Ideasbugs::Merge.call(source: source, target: target)
    rescue ArgumentError
      # The competing merge already made this target a merged source.
    end
    concurrently(-> { merge.call(first, second) }, -> { merge.call(second, first) })
    records = [first.reload, second.reload]
    assert_equal 1, records.count { |record| record.visibility == 'listed' }
    merged = records.find { |record| record.visibility == 'merged' }
    assert_equal 'listed', merged.merged_into.visibility
  end

  test 'default board creation for a new tenant is race safe' do
    tenant = SecureRandom.hex(8)
    concurrently(-> { Ideasbugs::Board.default_for(tenant) }, -> { Ideasbugs::Board.default_for(tenant) })
    assert_equal 1, Ideasbugs::Board.for_tenant(tenant).count
  end
end
