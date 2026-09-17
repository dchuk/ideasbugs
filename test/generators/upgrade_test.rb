# frozen_string_literal: true

require 'test_helper'
require 'open3'

class UpgradeTest < Minitest::Test
  def run_migration(extra)
    root = File.expand_path('../..', __dir__)
    script = <<~RUBY
      require 'active_record'
      require 'active_support/all'
      require 'erb'
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
      ActiveRecord::Migration.verbose = false
      migration_version = '[7.1]'
      primary_key_type_option = ''
      eval ERB.new(File.read('#{root}/lib/generators/ideasbugs/install/templates/create_ideasbugs_feedbacks.rb.tt')).result(binding)
      eval ERB.new(File.read('#{root}/lib/generators/ideasbugs/upgrade/templates/upgrade_ideasbugs_to_v2.rb.tt')).result(binding)
      CreateIdeasbugsFeedbacks.migrate(:up)
      connection = ActiveRecord::Base.connection
      #{extra}
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', script)
    assert status.success?, "#{stdout}\n#{stderr}"
  end

  def test_empty_fresh_install_creates_private_default_and_required_relationships
    run_migration <<~RUBY
      UpgradeIdeasbugsToV2.migrate(:up)
      raise unless connection.select_value('SELECT COUNT(*) FROM ideasbugs_boards') == 1
      raise unless connection.select_value('SELECT visibility FROM ideasbugs_boards') == 'private'
      raise unless connection.columns(:ideasbugs_feedbacks).find { |c| c.name == 'board_id' }.null == false
      raise unless connection.foreign_keys(:ideasbugs_comments).size == 2
      raise unless connection.indexes(:ideasbugs_votes).any? { |i| i.unique && i.columns == %w[feedback_id voter_id] }
      begin
        UpgradeIdeasbugsToV2.migrate(:up)
        raise 'rerun accepted'
      rescue RuntimeError => e
        raise unless e.message.include?('already installed')
      end
    RUBY
  end

  def test_legacy_upgrade_preserves_content_and_partitions_default_boards
    run_migration <<~RUBY
      %w[open in_review resolved].each_with_index do |status, i|
        tenant = i == 0 ? 'NULL' : "'acme'"
        connection.execute("INSERT INTO ideasbugs_feedbacks (message, kind, status, tenant, author_id, section, created_at, updated_at) VALUES ('Keep this', 'bug', '\#{status}', \#{tenant}, 'opaque-author', 'Legacy', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
      end
      UpgradeIdeasbugsToV2.migrate(:up)
      rows = connection.select_all('SELECT * FROM ideasbugs_feedbacks ORDER BY id').to_a
      raise unless rows.map { |r| r['status'] } == %w[under_review under_review complete]
      raise unless rows.all? { |r| r['message'] == 'Keep this' && r['author_id'] == 'opaque-author' && r['section'] == 'Legacy' && r['visibility'] == 'unlisted' }
      raise unless rows[0]['board_id'] != rows[1]['board_id'] && rows[1]['board_id'] == rows[2]['board_id']
    RUBY
  end

  def test_unknown_status_fails_before_changing_schema
    run_migration <<~RUBY
      connection.execute("INSERT INTO ideasbugs_feedbacks (message, status, created_at, updated_at) VALUES ('Keep', 'surprise', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
      begin
        UpgradeIdeasbugsToV2.migrate(:up)
        raise 'unknown status accepted'
      rescue RuntimeError => e
        raise unless e.message.include?('Unknown Ideasbugs statuses')
      end
      raise if connection.table_exists?(:ideasbugs_boards)
    RUBY
  end
end
