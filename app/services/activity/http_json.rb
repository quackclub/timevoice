require "net/http"
require "json"

module Activity
  class HttpJson
    class Error < StandardError; end

    def initialize(base_url, headers = {})
      @base = URI(base_url)
      @headers = headers
    end

    def get(path, query = {})
      uri = @base.dup
      uri.path = path.start_with?("/") ? path : "#{@base.path}/#{path}"
      uri.query = URI.encode_www_form(query.compact) if query.any?
      response = request(uri)
      [ JSON.parse(response.body.presence || "null"), response ]
    end

    def get_url(url)
      response = request(URI(url))
      [ JSON.parse(response.body.presence || "null"), response ]
    end

    private

    MAX_RETRIES = 3

    def request(uri, attempt = 1)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 60) do |http|
        req = Net::HTTP::Get.new(uri)
        @headers.each { |k, v| req[k] = v }
        http.request(req)
      end
      return res if res.is_a?(Net::HTTPSuccess)

      if rate_limited?(res) && attempt < MAX_RETRIES
        sleep retry_delay(res, attempt)
        return request(uri, attempt + 1)
      end
      raise Error, "#{uri.host}#{uri.path} returned #{res.code}: #{res.body.to_s[0, 200]}"
    end

    def rate_limited?(res)
      res.code == "429" || (res.code == "403" && res.body.to_s.include?("rate limit"))
    end

    def retry_delay(res, attempt)
      if res["retry-after"].present?
        res["retry-after"].to_i
      elsif res["x-ratelimit-reset"].present? && res["x-ratelimit-remaining"] == "0"
        (res["x-ratelimit-reset"].to_i - Time.now.to_i).clamp(1, 120)
      else
        20 * attempt
      end
    end
  end
end
