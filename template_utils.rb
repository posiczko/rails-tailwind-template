# frozen_string_literal: true

require "fileutils"
require "shellwords"

def active_job_sidekiq?
  options[:async_job] == "sidekiq"
end

def add_authentication
  log_action ". Adding authentication"
  if authentication_devise?
    add_authentication_devise
  else
    add_authentication_rodauth
  end
end

def add_authentication_devise
  log_action ". Adding authentication devise"
  add_gem "devise"
  add_gem "devise-tailwindcssed"

  inject_into_file "config/environments/development.rb",
                   "  config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
                   before: /^end/

  run "bundle install"
  generate "devise:install"
  generate "devise:views:tailwindcssed"
  generate :devise, "User", "first_name", "last_name", "admin:boolean"

  # set admin boolean to false by default
  in_root do
    migration = Dir.glob("db/migrate/*").max_by { |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  # name_of_person gem
  append_to_file("app/models/user.rb", "\nhas_person_name\n", after: "class User < ApplicationRecord")

  inject_into_file "config/initializers/devise.rb", "  config.navigational_formats = ['/', :html, :turbo_stream]", after: "Devise.setup do |config|\n"

  inject_into_file 'config/initializers/devise.rb', after: "# frozen_string_literal: true\n" do
    <<~EOF
      class TurboFailureApp < Devise::FailureApp
        def respond
          if request_format == :turbo_stream
            redirect
          else
            super
          end
        end
        def skip_format?
          %w(html turbo_stream */*).include? request_format.to_s
        end
      end
    EOF
  end

  inject_into_file 'config/initializers/devise.rb', after: "# ==> Warden configuration\n" do
    <<-EOF
  config.warden do |manager|
    manager.failure_app = TurboFailureApp
  end
    EOF
  end

  gsub_file "config/initializers/devise.rb", /  # config.secret_key = .+/, "  config.secret_key = Rails.application.credentials.secret_key_base"
end

def add_authentication_rodauth
  log_action ". Adding authentication rodauth"
  add_gem "rodauth-rails"
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
  add_gem("friendly_id", "~> 5.5.0")
  add_gem("madmin")
  add_gem("name_of_person", "~> 1.1.1")
  if active_job_sidekiq?
    add_gem("sidekiq", "~> 7.0.2")
  else
    add_gem("good_job")
  end
  add_gem("sitemap_generator", "~> 6.3.0")
  add_gem("whenever", require: false)
  add_gem("responders", github: "heartcombo/responders", branch: "main")

  gem_group :development do
    gem "rack-livereload"
    gem "guard-livereload"
  end

  gem_group :code_quality do
    gem "brakeman"
    gem "bundler-audit"
    gem "bundler-leak"
    gem "caliber"
    gem "git-lint"
    gem "reek"
    gem "rubocop-shopify"
  end
end

def add_goodjob
  log_action ". Adding goodjob"
  generate("good_job:install")
  environment("config.active_job.queue_adapter = :good_job")
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

def authentication_devise?
  options[:authentication] == "devise"
end

def configure_rubocop
  log_action ". Adding rubocop"
  copy_file(".rubocop.yml")

  content = <<-'RUBY'
return if require_error.nil? &&
  Gem::Requirement.new(bundler_requirement).satisfied_by?(Gem::Version.new(Bundler::VERSION))
  RUBY
  gsub_file "bin/bundle",
            "return if require_error.nil? && Gem::Requirement.new(bundler_requirement).satisfied_by?(Gem::Version.new(Bundler::VERSION))",
            content

  content = <<-'RUBY'

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
  if js_importmap?
    # rails tailwindcss:install already ran
    %i[@tailwindcss/typography @tailwindcss/forms @tailwindcss/aspect-ratio @tailwindcss/line-clamp].each do |js_package|
      pin_js_package(js_package)
    end
    # we rely on ordering here: Procfile.dev for either goodjob or sidekiq is already copied
    # add appropriate line for tailwind css compile
    gsub_file "Procfile.dev", /css: yarn build:css --watch/, "css: bin/rails tailwindcss:watch"
    content = <<-ERB
  <%= csp_meta_tag %>

  <%= stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload" %>
    ERB
    gsub_file("app/views/shared/_head.html.erb", /^.*<%= csp_meta_tag %>.*$/, content)
  else
    remove_file "tailwind.config.js"
    run "yarn add -D @tailwindcss/typography @tailwindcss/forms @tailwindcss/aspect-ratio @tailwindcss/line-clamp"
    copy_file "templates/tailwind.config.js", "tailwind.config.js"
  end
end

def add_javascript_packages
  log_action ". Adding javascript packages"
  if !js_importmap?
    run "yarn add local-time"
  else
    pin_js_package("local-time")
    append_to_file("app/javascript/application.js", "import LocalTime from 'local-time'\nLocalTime.start()\n")
  end
end

def copy_templates
  log_action ". Copying templates"

  # remove_file("app/assets/stylesheets/application.css")
  # remove_file("app/javascript/application.js")
  # remove_file("app/javascript/controllers/index.js")

  remove_file("Procfile.dev")
  if active_job_sidekiq?
    copy_file("templates/Procfile.dev.sidekiq", "Procfile.dev")
  else
    copy_file("templates/Procfile.dev.goodjob", "Procfile.dev")
  end
  if js_importmap?
    gsub_file "Procfile.dev", /js: yarn build --watch/, ""
  end

  remove_file "app/controllers/application_controller.rb"
  remove_file "app/views/shared/_navbar.html.erb"
  remove_file "app/controllers/rodauth_controller.rb"
  if authentication_devise?
    copy_file("templates/app/controllers/application_controller.rb.devise", "app/controllers/application_controller.rb")
    copy_file("templates/app/views/shared/_navbar.html.erb.devise", "app/views/shared/_navbar.html.erb")
  else
    copy_file("templates/app/controllers/application_controller.rb.rodauth", "app/controllers/application_controller.rb")
    copy_file("templates/app/controllers/rodauth_controller.rb.rodauth", "app/controllers/rodauth_controller.rb")
    copy_file("templates/app/views/shared/_navbar.html.erb.rodauth", "app/views/shared/_navbar.html.erb")
  end

  remove_file "app/views/shared/_head.html.erb"
  if js_importmap?
    copy_file("templates/app/views/shared/_head.html.erb.importmap", "app/views/shared/_head.html.erb")
  else
    copy_file("templates/app/views/shared/_head.html.erb.esbuild", "app/views/shared/_head.html.erb")
  end

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

def js_importmap?
  options[:javascript] == "importmap"
end

def log_action(message)
  say
  say message, :blue
  say
end

def parse_additional_args
  # args will contain additional arguments that are not recognized
  # as a standard rails arguments, let's merge them
  additional_args = HashWithIndifferentAccess[@args.flat_map { |s| s.scan(/--?([^=\s]+)(?:=(\S+))?/) }]
  @options        = options.merge(additional_args)
end

def pin_js_package(package_name)
  append_to_file("config/importmap.rb", "# #{package_name}\n")
  run "./bin/importmap pin #{package_name}"

end

def set_application_name
  log_action ". Setting application name"

  # Add Application Name to Config
  environment("config.application_name = Rails.application.class.module_parent_name")

  # Announce the user where they can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end
