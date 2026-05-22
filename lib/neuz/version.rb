module Neuz
  VERSION = "0.1.2".freeze

  def self.version
    ENV["NEUZ_VERSION"] || VERSION
  end
end
