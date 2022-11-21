=begin
Instructions: $ rails new myapp -d postgresql -m template.rb
rails new myapp \
  --skip-jbuilder \
  --skip-test \
  --skip-system-test \
  --css=tailwind \
  --asset-pipeline=propshaft \
  --database=postgresql \
  --javascript=esbuild \
  -m template.rb
=end

# frozen_string_literal: true

require_relative "template_utils.rb"

#
# Main
#

add_template_repository_to_source_path
default_to_esbuild
add_gems

after_bundle do
  set_application_name
  add_authentication
  add_authorization
  add_javascript_packages
  add_sidekiq
  add_rspec
  add_friendly_id
  add_whenever
  add_sitemap
  configure_rubocop
  # add_esbuild_script
  # rails_command "active_storage:install" # needs auth

  # Make sure Linux is in the Gemfile.lock for deploying
  run "bundle lock --add-platform x86_64-linux"

  copy_templates
  configure_tailwind

  # Commit everything to git
  unless ENV["SKIP_GIT"]
    git :init
    git add: "."
    # git commit will fail if user.email is not configured
    begin
      git(commit: %( -m 'Initial commit' ))
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
