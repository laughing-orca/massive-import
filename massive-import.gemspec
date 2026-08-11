Gem::Specification.new do |s|
  s.name            = "massive-import"
  s.version         = File.read(File.expand_path('VERSION', __dir__)).strip
  s.summary         = "execute massive imports!"
  s.description     = "execute massive imports!"
  s.authors         = ["Laughing Orca"]
  s.email           = "trulyop100@gmail.com"
  s.homepage        = "https://github.com/laughing-orca/massive-import"
  s.files           = Dir['VERSION', 'lib/**/*.rb']

  s.add_dependency "activerecord", "~> 8.1"
  s.add_dependency "mysql2", "~> 0.5"
  s.add_dependency "sidekiq", "~> 8.1"
  s.add_dependency "webrick", "~> 1.9"
  s.add_dependency "rack", "~> 3.2"
  s.add_dependency "rack-session", "~> 2.1"
  s.add_dependency "rackup", "~> 2.3"

  s.add_development_dependency "byebug", "~> 13.0"
end
