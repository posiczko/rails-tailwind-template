# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "thor"

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

def configure_friendly_id
  log_action ". Adding friendly_id"

  generate "friendly_id"
  insert_into_file(Dir["db/migrate/**/*friendly_id_slugs.rb"].first, "[7.1]", after: "ActiveRecord::Migration")
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
  add_gem("friendly_id")
  add_gem("madmin")
  add_gem("name_of_person")
  if active_job_sidekiq?
    add_gem("sidekiq", "~> 7.2.4")
  else
    add_gem("solid_queue")
  end
  add_gem("sitemap_generator")
  add_gem("whenever", require: false)
  # add_gem("responders", github: "heartcombo/responders", branch: "main")

  gem_group :development do
    gem "hotwire-rails"
    gem "hotwire-livereload"
  end

  gem_group :code_quality do
    gem "brakeman"
    gem "bundler-audit"
    gem "bundler-leak"
    gem "caliber"
    gem "git-lint"
    gem "reek"
    gem "rubocop-shopify", require: false
  end
end

def add_and_configure_hotwire_livereload
  log_action ". Adding hotwire livereload gem for dev"
  log_action "    Add non-standard directories you want to livereload to development.rb environment via config.hotwire_livereload.listen_paths"
  log_action "    See https://github.com/kirillplatonov/hotwire-livereload for more information"
  create_file "config/initializers/hotwire-livereload.rb" do
    <<~RUBY
      Rails.application.configure do
        if Rails.env.development?
          # Configure debounce delay for livereload
          config.hotwire_livereload.debounce_delay_ms = 300 # in milliseconds
        end
      end
    RUBY
  end
end

def configure_solid_que
  log_action ". Adding solid_que"
  generate("solid_queue:install")
end

def configure_sitemap
  log_action ". Adding sitemap"

  rails_command "sitemap:install"
end

def configure_sidekiq
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

def add_and_configure_rspec
  log_action ". Adding rspec"
  gem_group :development, :test do
    gem "capybara"
    gem "capybara-screenshot"
    gem "rspec-rails"
    gem "selenium-webdriver"
  end

  run "bundle install"
  rails_command "generate rspec:install"

  empty_directory "spec/support", force: true
  copy_file "templates/spec/support/chromedriver.rb", "spec/support/chromedriver.rb"

  insert_into_file "spec/rails_helper.rb",
                   "require \"support/chromedriver\"\n",
                   after: "require 'rspec/rails'\n"
  uncomment_lines "spec/rails_helper.rb", /Rails.root.glob\(\'spec\/support\/\*\*\/\*.rb\'\).sort.each \{ |f| require f \}/
end

def configure_whenever
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
  gem_group :development do
    gem "guard-rspec", require: false
  end

  create_file "Guardfile" do
    <<~GUARD
      guard "rspec", cmd: "bundle exec rspec" do
        require "guard/rspec/dsl"
        dsl = Guard::RSpec::Dsl.new(self)
      
        # RSpec files
        rspec = dsl.rspec
        watch(rspec.spec_helper) { rspec.spec_dir }
        watch(rspec.spec_support) { rspec.spec_dir }
        watch(rspec.spec_files)
      
        # Rails files
        rails = dsl.rails(view_extensions: %w[erb haml slim])
        dsl.watch_spec_files_for(rails.app_files)
        dsl.watch_spec_files_for(rails.views)
      
        # Rails config changes
        watch(rails.spec_helper) { rspec.spec_dir }
        watch(rails.routes) { "\#{rspec.spec_dir}/features" }
        watch(rails.app_controller) { "\#{rspec.spec_dir}/features" }
      
        watch(rails.controllers) do |m|
          [
            rspec.spec.call("routing/\#{m[1]}_routing"),
            rspec.spec.call("features/\#{m[1]}")
          ]
        end
      
        # Capybara features specs
        watch(rails.view_dirs) { |m| rspec.spec.call("features/\#{m[1]}") }
        watch(rails.layouts) { |m| rspec.spec.call("features/\#{m[1]}") }
      end      
    end
    GUARD
  end
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

def configure_authentication
  if authentication_devise?
    insert_into_file("app/controllers/application_controller.rb",
                     "protect_from_forgery with: :reset_session\n",
                     after: "class ApplicationController < ActionController::Base\n")
    #  copy_file("templates/app/views/shared/_navbar.html.erb.devise", "app/views/shared/_navbar.html.erb")
  else
    content = <<-RUBY
      protect_from_forgery with: :exception

      def current_account
        rodauth.rails_account
      end

      def user_signed_in?
        rodauth.rails_account.present?
      end

      helper_method :current_account
      helper_method :user_logged_in?
    RUBY
    insert_into_file("app/controllers/application_controller.rb",
                     content,
                     after: "class ApplicationController < ActionController::Base\n")
    #  copy_file("templates/app/views/shared/_navbar.html.erb.rodauth", "app/views/shared/_navbar.html.erb")
  end
end

def create_home_controller
  log_action ". Creating home controller"
  generate :controller, "home", %w[index terms privacy]
  route "root to: 'home#index'"
  remove_file "spec/views/home"
  remove_file "app/helpers/home_helper.rb"
  remove_file "spec/helpers/home_helper_spec.rb"
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
    copy_file("templates/Procfile.dev.solid_que", "Procfile.dev")
  end

  if js_importmap?
    gsub_file "Procfile.dev", /js: yarn build --watch/, ""
  end

  if authentication_devise?
    copy_file("templates/app/views/shared/_navbar.html.erb.devise", "app/views/shared/_navbar.html.erb")
  else
    copy_file("templates/app/views/shared/_navbar.html.erb.rodauth", "app/views/shared/_navbar.html.erb")
  end

  if js_importmap?
    copy_file("templates/app/views/shared/_head.html.erb.importmap", "app/views/shared/_head.html.erb")
  else
    copy_file("templates/app/views/shared/_head.html.erb.esbuild", "app/views/shared/_head.html.erb")
    # copy_file("config/esbuild.config.js")
  end

  # copy_file("app/javascript/application.js")
  # copy_file("app/javascript/controllers/index.js")
  #
  # directory("config", force: true)
  empty_directory("lib/erb/scaffold", force: true)
  directory("templates/lib/templates/erb/scaffold", "lib/erb/scaffold")
  copy_file "templates/spec/support/chromedriver.rb", "spec/support/chromedriver.rb"
  copy_file(".reek.yml")

  comment_lines "Gemfile", /^ruby "3.3.1"$/
  insert_into_file("Gemfile", "ruby file: \".ruby-version\"\n", after: "source \"https://rubygems.org\"\n")
end

def default_to_esbuild
  log_action ". Defaulting to esbuild"

  return if options[:javascript] == "esbuild"

  unless options[:skip_javascript]
    @options = options.merge(javascript: "esbuild")
  end
end

def default_to_importmap
  log_action ". Defaulting to importmap"

  return if options[:javascript] == "importmap"

  unless options[:skip_javascript]
    @options = options.merge(javascript: "importmap")
  end
end

def gem_exists?(name)
  File.read("Gemfile") =~ /^\s*gem ['"]#{name}['"]/
end

def js_importmap?
  options[:javascript] == "importmap"
end

def js_esbuild?
  options[:javascript] == "esbuild"
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
