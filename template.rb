=begin
Instructions: $ rails new myapp -d postgresql -m template.rb
rails new myapp \
  --skip-jbuilder \
  --skip-test \
  --skip-system-test \
  --css=tailwind \
  --asset-pipeline=propshaft \
  --database=postgresql \
  --javascript=esbuild \ # [esbuild|importmap] - default improtmap
  --async_job=[solid_que|sidekiq] \ # default solid_que
  --authentication=[devise|rodauth] \ # default rodauth
  -m template.rb

rails new myapp \
        --skip-jbuilder \
        --skip-test \
        --skip-system-test \
        --css=tailwind \
        --asset-pipeline=propshaft \
        --database=postgresql \
        --authentication=devise \
        --javascript=importmap -m template.rb

=end

# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"
require_relative "template_utils.rb"

#
# Main

parse_additional_args
add_template_repository_to_source_path
default_to_importmap unless js_esbuild?
add_gems

after_bundle do
  set_application_name
  add_authentication
  add_authorization
  add_javascript_packages
  if active_job_sidekiq?
    configure_sidekiq
  else
    configure_solid_que
  end
  add_and_configure_rspec
  configure_friendly_id
  configure_whenever
  configure_sitemap
  add_and_configure_hotwire_livereload
  # TODO: add_esbuild_script
  # TODO: rails_command "active_storage:install" # needs auth

  # Make sure Linux is in the Gemfile.lock for deploying
  run "bundle lock --add-platform x86_64-linux"

  copy_templates
  configure_authentication
  # configure_tailwind
  configure_guard
  configure_rubocop

  create_home_controller

  exit

  # Commit everything to git
  run "rubocop -A"
  unless ENV["SKIP_GIT"]
    git :init
    git add: "."
    # git commit will fail if user.email is not configured
    begin
      git(commit: %( -m 'Added initial commit' ))
    rescue StandardError => e
      puts e.message
    end
  end

  say
  say "App successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{original_app_name}"
  say
  say "  # Update config/database.yml with your database credentials"
  say
  say "  rails db:create db:migrate"
  say "  rails g madmin:install # Generate admin dashboards"
  say "  bin/dev"
end
