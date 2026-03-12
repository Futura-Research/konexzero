module Cloudflare
  class Calls < HttpClient
    BASE_URL = "https://rtc.live.cloudflare.com/v1".freeze

    def initialize(
      app_id: Rails.application.config.cloudflare.app_id,
      token: Rails.application.config.cloudflare.api_token
    )
      @app_id = app_id
      @token = token
    end

    # Creates a new SFU session on Cloudflare.
    # A session maps 1:1 to a WebRTC PeerConnection.
    #
    # @return [Hash] { "sessionId" => "..." }
    def create_session
      http_post("#{BASE_URL}/apps/#{@app_id}/sessions/new", {})
    end

    # Adds local (publish) or remote (subscribe) tracks to a session.
    #
    # @param session_id [String] Cloudflare session ID
    # @param tracks [Array<Hash>] each: { location:, trackName:, mid:, sessionId: (remote only) }
    # @param session_description [Hash, nil] { sdp:, type: } — required for publish, nil for subscribe
    # @return [Hash] { "sessionDescription" => {...}, "tracks" => [...], "requiresImmediateRenegotiation" => bool }
    def add_tracks(session_id, tracks:, session_description: nil)
      body = { tracks: tracks }
      if session_description && session_description[:sdp].present?
        body[:sessionDescription] = {
          sdp: session_description[:sdp],
          type: session_description[:type]
        }
      end
      http_post("#{BASE_URL}/apps/#{@app_id}/sessions/#{session_id}/tracks/new", body)
    end

    # Closes tracks in a session.
    #
    # @param session_id [String]
    # @param track_mids [Array<String>] MID identifiers to close (or ['*'] for all)
    # @param force [Boolean] force-close without SDP renegotiation
    # @return [Hash] { "tracks" => [...], "sessionDescription" => {...} }
    def close_tracks(session_id, track_mids:, force: false)
      body = {
        tracks: track_mids.map { |mid| { mid: mid } },
        force: force
      }
      http_put("#{BASE_URL}/apps/#{@app_id}/sessions/#{session_id}/tracks/close", body)
    end

    # Renegotiates a session (sends SDP answer after subscribe).
    #
    # @param session_id [String]
    # @param session_description [Hash] { sdp:, type: }
    # @return [Hash] { "sessionDescription" => {...} } or {}
    def renegotiate(session_id, session_description:)
      body = {
        sessionDescription: {
          sdp: session_description[:sdp],
          type: session_description[:type]
        }
      }
      http_put("#{BASE_URL}/apps/#{@app_id}/sessions/#{session_id}/renegotiate", body)
    end

    # Retrieves current session state from Cloudflare.
    #
    # @param session_id [String]
    # @return [Hash] { "tracks" => [{ "location" => ..., "mid" => ..., "status" => ... }] }
    def get_session(session_id)
      http_get("#{BASE_URL}/apps/#{@app_id}/sessions/#{session_id}")
    end

    private

    def api_token = @token
  end
end
