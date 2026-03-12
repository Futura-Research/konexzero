module Api
  module V1
    class CredentialsController < BaseController
      include WebrtcConcern

      # POST /api/v1/credentials
      #
      # Generates short-lived TURN/STUN ICE server credentials.
      # Optional body: { "ttl": 86400 }
      def create
        ttl = params.fetch(:ttl, 86_400).to_i.clamp(300, 86_400)
        response = cf_turn.generate_ice_servers(ttl: ttl)

        render json: {
          data: { ice_servers: Array.wrap(response["iceServers"]) },
          meta: render_meta
        }
      rescue Cloudflare::HttpClient::ApiError => e
        handle_cf_error(e)
      end
    end
  end
end
