# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'crono_trigger/version'

Gem::Specification.new do |spec|
  spec.name          = "crono_trigger"
  spec.version       = CronoTrigger::VERSION
  spec.authors       = ["joker1007"]
  spec.email         = ["kakyoin.hierophant@gmail.com"]

  spec.summary       = %q{In Service Asynchronous Job Scheduler for Rails}
  spec.description   = %q{In Service Asynchronous Job Scheduler for Rails. This gem handles ActiveRecord model as schedule definition.}
  spec.homepage      = "https://github.com/joker1007/crono_trigger"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|screenshots)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]


  spec.add_dependency "chrono", ">= 0.6.0"
  spec.add_dependency "serverengine"
  spec.add_dependency "concurrent-ruby", ">= 1.1.10"
  spec.add_dependency "tzinfo"
  spec.add_dependency "sinatra"
  spec.add_dependency "rack-contrib"
  spec.add_dependency "oj"
  spec.add_dependency "activerecord", ">= 4.2"
  spec.add_dependency "retriable"

  spec.add_development_dependency "sqlite3", ">= 1.3"
  spec.add_development_dependency "mysql2"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "rollbar"
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "simplecov-cobertura"
end
