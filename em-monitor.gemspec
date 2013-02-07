Gem::Specification.new do |gem|
  gem.name = 'em-monitor'
  gem.version = '0.1'

  gem.summary = 'Monitor the distribution of your eventmachine CPU usage'
  gem.description = "EventLoops are awesome unless you're doing a lot of blocking CPU stuff, at which point they become useless.
                     This gem lets you easily graph the lengths of CPU-blocked spans so that you can take action to make your
                     eventmachine server faster"

  gem.authors = ['Conrad Irwin']
  gem.email = %w(conrad@rapportive.com)
  gem.homepage = 'http://github.com/ConradIrwin/em-monitor'

  gem.license = 'MIT'

  gem.required_ruby_version = '>= 1.9.3'

  gem.add_dependency 'eventmachine'
  gem.add_dependency 'lspace'

  gem.files = `git ls-files`.split("\n")
end
