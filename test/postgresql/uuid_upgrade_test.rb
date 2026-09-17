# frozen_string_literal: true

require 'test_helper'
require 'open3'

class UuidUpgradeTest < Minitest::Test
  def test_uuid_host_upgrade_preserves_uuid_relationships
    root = File.expand_path('../..', __dir__)
    script = <<~RUBY
      require 'active_record'
      require 'active_support/all'
      require 'erb'
      ActiveRecord::Base.establish_connection(ENV.fetch('DATABASE_URL'))
      connection = ActiveRecord::Base.connection
      schema = 'ideasbugs_uuid_' + SecureRandom.hex(6)
      connection.create_schema(schema)
      begin
        connection.schema_search_path = schema
        ActiveRecord::Migration.verbose = false
        migration_version = '[7.1]'
        primary_key_type_option = ', id: :uuid'
        eval ERB.new(File.read('#{root}/lib/generators/ideasbugs/install/templates/create_ideasbugs_feedbacks.rb.tt')).result(binding)
        eval ERB.new(File.read('#{root}/lib/generators/ideasbugs/upgrade/templates/upgrade_ideasbugs_to_v2.rb.tt')).result(binding)
        CreateIdeasbugsFeedbacks.migrate(:up)
        connection.execute("INSERT INTO ideasbugs_feedbacks (message, created_at, updated_at) VALUES ('Keep', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
        UpgradeIdeasbugsToV2.migrate(:up)
        raise unless connection.columns(:ideasbugs_feedbacks).find { |c| c.name == 'board_id' }.type == :uuid
        raise unless connection.columns(:ideasbugs_votes).find { |c| c.name == 'feedback_id' }.type == :uuid
        raise unless connection.select_value('SELECT status FROM ideasbugs_feedbacks') == 'under_review'
      ensure
        connection.schema_search_path = 'public'
        connection.drop_schema(schema, if_exists: true)
      end
    RUBY
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-e', script)
    assert status.success?, "#{stdout}\n#{stderr}"
  end
end
