require "bundler/setup"
require "massive-import"

MassiveImport::DashboardServer.new.start
