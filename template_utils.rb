# frozen_string_literal: true

require "fileutils"
require "shellwords"

# Copied from: https://github.com/mattbrictson/rails-template
# Add this template directory to source_paths so that Thor actions like
# copy_file and template resolve against our source files. If this file was
# invoked remotely via HTTP, that means the files are not present locally.
# In that case, use `git clone` to download them to a local temporary dir.
def add_authorization
  say "\n. Adding authorization policy\n", :blue

  rails_command("generate action_policy:install")
end

def add_friendly_id
  say "\n. Adding friendly_id\n", :blue

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
  say "\n. Adding gems\n", :blue

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
  say "\n. Adding sitemap\n", :blue

  rails_command("sitemap:install")
end

def add_sidekiq
  say "\n. Adding sidekiq\n", :blue

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
  say "\n. Adding rspec\n", :blue
  gem_group :development, :test do
    gem "rspec-rails"
  end

  run "bundle install"
  rails_command "generate rspec:install"
end

def add_whenever
  say "\n. Adding whenever\n", :blue
  run("wheneverize .")
end

def configure_rubocop
  say "\n. Adding rubocop\n", :blue
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

  run "rubocop -A"
end

def configure_tailwind
  say "\n. Configuring tailwind\n", :blue
  remove_file "tailwind.config.js"
  run "yarn add -D @tailwindcss/typography @tailwindcss/forms @tailwindcss/aspect-ratio @tailwindcss/line-clamp"
  copy_file "tailwind.config.js"
end

def add_javascript_packages
  say "\n. Adding javascript packages\n", :blue
  run "yarn add local-time"
end

def copy_templates
  say "\n. Copying templates\n", :blue

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
  #
  directory "app", force: true
  directory "lib", force: true
  route("get '/terms', to: 'home#terms'")
  route("get '/privacy', to: 'home#privacy'")
end

def default_to_esbuild
  say "\n. Defaulting to esbuild\n", :blue

  return if options[:javascript] == "esbuild"

  unless options[:skip_javascript]
    @options = options.merge(javascript: "esbuild")
  end
end

def gem_exists?(name)
  File.read("Gemfile") =~ /^\s*gem ['"]#{name}['"]/
end

def set_application_name
  say "\n. Setting application name\n", :blue

  # Add Application Name to Config
  environment("config.application_name = Rails.application.class.module_parent_name")

  # Announce the user where they can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end
