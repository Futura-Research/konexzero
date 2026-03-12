module Cloudflare
  class Turn < HttpClient
    BASE_URL = "https://rtc.live.cloudflare.com".freeze

    def initialize(
      key_id: Rails.application.config.cloudflare.turn_key_id,
      token: Rails.application.config.cloudflare.turn_key_api_token
    )
      @key_id = key_id
      @token = token
    end

    # Generates short-lived TURN/STUN ICE server credentials.
    #
    # The returned hash can be passed directly to `new RTCPeerConnection({ iceServers: ... })`
    # on the client.
    #
    # @param ttl [Integer] credential lifetime in seconds (default 24h)
    # @return [Hash] { "iceServers" => [{ "urls" => [...], "username" => "...", "credential" => "..." }] }
    def generate_ice_servers(ttl: 86_400)
      http_post(
        "#{BASE_URL}/v1/turn/keys/#{@key_id}/credentials/generate-ice-servers",
        { ttl: ttl }
      )
    end

    private

    def api_token = @token
  end
end
