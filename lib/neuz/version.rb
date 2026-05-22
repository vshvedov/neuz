module Neuz
  VERSION = "0.1.3".freeze

  def self.version
    ENV["NEUZ_VERSION"] || VERSION
  end
end
