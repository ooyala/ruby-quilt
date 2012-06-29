Gem::Specification.new do |s|
  s.name        = 'ruby-quilt'
  s.version     = '0.2.2'
  s.summary     = "A File stitcher"
  s.description = "A file stitcher that maintains versions and can fetch additional versions from a server."
  s.authors     = ["Jigish Patel"]
  s.email       = 'x-device-team@ooyala.com'
  s.files       = ["lib/quilt.rb", "lib/lru_cache.rb", "lib/quilt/eventmachine.rb"]
  s.homepage    = 'http://github.com/ooyala/ruby-quilt'
  s.add_runtime_dependency 'json', '~> 1.6', '>= 1.6.6'
  s.add_runtime_dependency 'popen4', '~> 0.1', '>= 0.1.2'
  s.add_runtime_dependency 'ecology', '~> 0.0', '>= 0.0.14'
  s.add_runtime_dependency 'faraday', '~> 0.8', '>= 0.8.1'
  s.add_development_dependency 'rake', '~> 0.8', '>= 0.8.7'
  s.add_development_dependency 'scope', '~> 0.2', '>= 0.2.3'
  s.add_development_dependency 'simplecov', '~> 0.5', '>= 0.5.3'
  s.required_ruby_version = '>= 1.9.2'
  s.license = 'MIT'
end
