require "fileutils"

module Neuz
  # Loads palette CSS for a named theme. Resolution order: a file in the
  # operator's custom dir (on the data volume) wins over a built-in of the
  # same name; an unknown/invalid name falls back to "default"; if even
  # default.css is unreadable, a hardcoded baseline keeps the UI styled.
  module Theme
    module_function

    NAME_RE = /\A[a-z0-9_-]+\z/

    FALLBACK_CSS = <<~CSS
      :root{--paper:250 249 246;--ink:23 23 27;--faint:115 115 122;--rule:225 224 220;--tag:239 238 233;--accent:185 95 45;--good:20 120 80;--bad:180 50 50;--cell-1:225 224 220;--cell-2:205 200 180;--cell-3:185 95 45}
      html.dark{--paper:16 16 18;--ink:236 235 230;--faint:140 140 145;--rule:40 40 44;--tag:30 30 34;--accent:238 142 90;--good:100 200 150;--bad:240 110 110;--cell-1:40 40 44;--cell-2:90 60 40;--cell-3:238 142 90}
    CSS

    def css(name)
      key = name.to_s
      cache = (@cache ||= {})
      return cache[key] if cache.key?(key)

      cache[key] = load_css(key)
    end

    def active_css
      css(Config.theme)
    end

    def reset_cache!
      @cache = {}
    end

    def load_css(name)
      path = resolve(name)
      return File.read(path) if path

      default_path = (resolve("default") unless name == "default")
      return File.read(default_path) if default_path

      FALLBACK_CSS
    end

    def resolve(name)
      return nil unless name.match?(NAME_RE)

      [Config.custom_themes_dir, Config.themes_dir].each do |dir|
        candidate = File.join(dir, "#{name}.css")
        return candidate if File.file?(candidate)
      end
      nil
    end
  end
end
