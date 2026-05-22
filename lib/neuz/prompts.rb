module Neuz
  module Prompts
    module_function

    def interview(url:, api_key:)
      render("interview.md", url, api_key)
    end

    def recurring(url:, api_key:)
      render("recurring.md", url, api_key)
    end

    def render(template, url, api_key)
      path = File.join(Config.prompts_dir, template)
      File.read(path)
        .gsub("{{NEUZ_URL}}", url.to_s)
        .gsub("{{NEUZ_API_KEY}}", api_key.to_s)
    end
  end
end
