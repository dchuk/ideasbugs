# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb'].exclude('test/system/**/*', 'test/postgresql/**/*')
end

namespace :test do
  desc 'Run PostgreSQL concurrency tests against a disposable DATABASE_URL'
  Rake::TestTask.new(:postgresql) do |t|
    t.libs << 'test'
    t.test_files = FileList['test/postgresql/**/*_test.rb']
  end

  desc 'Run browser (system) tests'
  Rake::TestTask.new(:system) do |t|
    t.libs << 'test'
    t.test_files = FileList['test/system/**/*_test.rb']
  end
end

task default: :test
