require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

pwd = File.expand_path('../', __FILE__)

gemfiles = Dir.glob(File.join(pwd, "gemfiles", "*.gemfile")).map { |f| File.basename(f, ".*") }

namespace :js do
  task :clean do
    rm_r(File.join(pwd, "web", "app", "build"))
    rm_r(File.join(pwd, "web", "public"))
  end

  task build: [:clean] do
    Dir.chdir(File.join(pwd, "web", "app"))
    sh({"PUBLIC_URL" => "<%= URI.parse(url('/')).path.chop %>"}, "npm run build") do |ok, res|
      raise "failed to build JS" unless ok

      mv(File.join(pwd, "web", "app", "build"), File.join(pwd, "web", "public"))
      mv(File.join(pwd, "web", "public", "index.html"), File.join(pwd, "web", "views", "index.erb"))
    end
  end
end

namespace :spec do
  gemfiles.each do |gemfile|
    desc "Run Tests by #{gemfile}.gemfile"
    task gemfile do
      Bundler.with_clean_env do
        sh "BUNDLE_GEMFILE='#{pwd}/gemfiles/#{gemfile}.gemfile' bundle install --path #{pwd}/.bundle"
        sh "BUNDLE_GEMFILE='#{pwd}/gemfiles/#{gemfile}.gemfile' bundle exec rake -t spec"
      end
    end
  end

  desc "Run All Tests"
  task :all do
    gemfiles.each do |gemfile|
      Rake::Task["spec:#{gemfile}"].invoke
    end
  end
end

namespace :bundle_update do
  gemfiles.each do |gemfile|
    desc "Run Tests by #{gemfile}.gemfile"
    task gemfile do
      Bundler.with_clean_env do
        sh "BUNDLE_GEMFILE='#{pwd}/gemfiles/#{gemfile}.gemfile' bundle update"
      end
    end
  end

  desc "Run All Tests"
  task :all do
    gemfiles.each do |gemfile|
      Rake::Task["bundle_update:#{gemfile}"].invoke
    end
  end
end
