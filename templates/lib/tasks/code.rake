# frozen_string_literal: true

begin
  require "brakeman"
  require "bundler/audit/task"
  require "bundler/plumber/task"
  require "bundler/setup"
  require "git/lint/rake/setup"
  require "reek/rake/task"
  require "rspec/core/rake_task"
  require "rubocop/rake_task"
rescue LoadError => error
  puts error.message
end

namespace :code do
  Bundler::Audit::Task.new
  Bundler::Plumber::Task.new
  Reek::Rake::Task.new
  RSpec::Core::RakeTask.new
  RuboCop::RakeTask.new

  desc "Run code quality checks"
  task quality: [:"bundle:leak", :git_lint, :reek, :rubocop]

  desc "Run brakeman"
  # rake code:brakeman[report.html]
  task :brakeman, :output_files do |_t, args|
    files = args[:output_files].split(" ") if args[:output_files]
    Brakeman.run(app_path: ".", output_files: files, print_report: true, pager: false)
  end

  desc "Run security checks (brakeman and bundle:audit)"
  task security: [:brakeman, :"bundle:audit"]
end
