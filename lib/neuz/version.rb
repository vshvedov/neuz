module Neuz
  VERSION = "0.1.0".freeze

  def self.version
    ENV["NEUZ_VERSION"] || VERSION
  end
end
