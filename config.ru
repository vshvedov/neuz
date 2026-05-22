$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "neuz"

Neuz.boot!
run Neuz::App.freeze.app
