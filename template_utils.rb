# frozen_string_literal: true

require "fileutils"
require "shellwords"

def add_authentication
  log_action ". Adding authentication"
  add_gem"rodauth-rails"
  run "bundle install"
  rails_command "generate rodauth:install"
  rails_command "generate rodauth:views"
  inject_into_file "config/environments/development.rb",
                   "  config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
                   before: /^end/
end

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_authorization
  log_action ". Adding authorization policy"

  rails_command "generate action_policy:install"
end

def add_friendly_id
  log_action ". Adding friendly_id"

  generate "friendly_id"
  insert_into_file(Dir["db/migrate/**/*friendly_id_slugs.rb"].first, "[5.2]", after: "ActiveRecord::Migration")
end

def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("jumpstart-"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git(clone: [
                 "--quiet",
                 "https://github.com/excid3/jumpstart.git",
                 tempdir,
               ].map(&:shellescape).join(" "))

    if (branch = __FILE__[%r{jumpstart/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git(checkout: branch) }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def add_gem(name, *options)
  gem(name, *options) unless gem_exists?(name)
end

def add_gems
  log_action ". Adding gems"

  add_gem("action_policy")
  add_gem("cssbundling-rails")
  add_gem("friendly_id", "~> 5.4.2")
  add_gem("madmin")
  add_gem("name_of_person", "~> 1.1.1")
  add_gem("sidekiq", "~> 7.0.1")
  add_gem("sitemap_generator", "~> 6.3.0")
  add_gem("whenever", require: false)
  add_gem("responders", github: "heartcombo/responders", branch: "main")

  gem_group :development do
    gem "rack-livereload"
    gem "guard-livereload"
  end

  gem_group :code_quality do
    gem "caliber"
    gem "rubocop-shopify"
  end
end

def add_sitemap
  log_action ". Adding sitemap"

  rails_command "sitemap:install"
end

def add_sidekiq
  log_action ". Adding sidekiq"

  environment("config.active_job.queue_adapter = :sidekiq")

  insert_into_file("config/routes.rb",
                   "require 'sidekiq/web'\n\n",
                   before: "Rails.application.routes.draw do")

  content = <<-RUBY
    #authenticate :user, lambda { |u| u.admin? } do
    #  mount Sidekiq::Web => "/sidekiq"
    #end
  RUBY
  insert_into_file("config/routes.rb", "#{content}\n\n", after: "Rails.application.routes.draw do\n")
end

def add_rspec
  log_action ". Adding rspec"
  gem_group :development, :test do
    gem "rspec-rails"
  end

  run "bundle install"
  rails_command "generate rspec:install"
end

def add_whenever
  log_action ". Adding whenever"
  run("wheneverize .")
end

def configure_rubocop
  log_action ". Adding rubocop"
  copy_file(".rubocop.yml")

  content = <<~'RUBY'
    return if require_error.nil? &&
      Gem::Requirement.new(bundler_requirement).satisfied_by?(Gem::Version.new(Bundler::VERSION))
  RUBY
  gsub_file "bin/bundle",
            "return if require_error.nil? && Gem::Requirement.new(bundler_requirement).satisfied_by?(Gem::Version.new(Bundler::VERSION))",
            content

  content = <<~'RUBY'

    warning = <<~END
      Activating bundler (#{bundler_requirement}) failed:
      #{gem_error.message}\n\nTo install the version of bundler this project requires, run `gem install bundler -v '#{bundler_requirement}'`"
    END
    warn(warning)

  RUBY
  gsub_file "bin/bundle",
            /warn \"Activating bundler .+$/,
            content

  say
  say "You can now run:"
  say "rubocop -A"
  say
end

def configure_guard
  log_action ". Configuring guard"
  run "bundle exec guard init livereload"
end

def configure_tailwind
  log_action ". Configuring tailwind"
  remove_file "tailwind.config.js"
  run "yarn add -D @tailwindcss/typography @tailwindcss/forms @tailwindcss/aspect-ratio @tailwindcss/line-clamp"
  copy_file "tailwind.config.js"
end

def add_javascript_packages
  log_action ". Adding javascript packages"
  run "yarn add local-time"
end

def copy_templates
  log_action ". Copying templates"

  # remove_file("app/assets/stylesheets/application.css")
  # remove_file("app/javascript/application.js")
  # remove_file("app/javascript/controllers/index.js")
  remove_file("Procfile.dev")
  copy_file("Procfile.dev")

  # copy_file("esbuild.config.js")
  # copy_file("app/javascript/application.js")
  # copy_file("app/javascript/controllers/index.js")
  #
  # directory("config", force: true)
  # directory("lib", force: true)

  directory "app", force: true
  directory "lib", force: true
  route("root to: 'home#index'")
  route("get '/terms', to: 'home#terms'")
  route("get '/privacy', to: 'home#privacy'")
end

def default_to_esbuild
  log_action ". Defaulting to esbuild"

  return if options[:javascript] == "esbuild"

  unless options[:skip_javascript]
    @options = options.merge(javascript: "esbuild")
  end
end

def gem_exists?(name)
  File.read("Gemfile") =~ /^\s*gem ['"]#{name}['"]/
end

def log_action(message)
  say 
  say message, :blue
  say 
end

def set_application_name
  log_action ". Setting application name"

  # Add Application Name to Config
  environment("config.application_name = Rails.application.class.module_parent_name")

  # Announce the user where they can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end
