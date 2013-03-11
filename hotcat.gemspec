# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'hotcat/version'

Gem::Specification.new do |gem|
  gem.name          = "hotcat"
  gem.version       = Hotcat::VERSION
  gem.authors       = ["Salsify"]
  gem.email         = ["info@salsify.com"]
  gem.description   = %q{Hotcat is a simple ETL framework that gets ICEcat data into Salsify.}
  gem.summary       = %q{Hotcat: ICEcat -> Salsify}
  gem.homepage      = "http://salsify.com/"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  #
  # external dependencies.
  #
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'rspec'
  gem.add_development_dependency 'railties'
  gem.add_dependency 'nokogiri', '~> 1.5.5'
  gem.add_dependency 'rubyzip', '~> 0.9.9'
end