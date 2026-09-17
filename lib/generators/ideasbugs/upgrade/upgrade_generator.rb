# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'
require_relative '../migration_helpers'

module Ideasbugs
  module Generators
    class UpgradeGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      include MigrationHelpers

      source_root File.expand_path('templates', __dir__)
      desc 'Upgrades Ideasbugs 1.x to feedback boards. Back up your database first.'

      def create_migration_file
        migration_template 'upgrade_ideasbugs_to_v2.rb.tt', 'db/migrate/upgrade_ideasbugs_to_v2.rb'
      end
    end
  end
end
