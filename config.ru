Encoding.default_external = Encoding::UTF_8

require 'sidekiq/web'
require 'rack/session/cookie'
require 'securerandom'

use Rack::Session::Cookie, secret: SecureRandom.hex(32), max_age: 86400
run Sidekiq::Web