module Neuz
  VERSION = "0.1.5".freeze

  def self.version
    ENV["NEUZ_VERSION"] || VERSION
  end
end
