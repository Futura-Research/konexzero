module WebrtcHelpers
  def api_headers(app_id:, api_key:, participant_id: nil)
    headers = {
      "X-App-Id" => app_id,
      "X-Api-Key" => api_key,
      "Content-Type" => "application/json"
    }
    headers["X-Participant-Id"] = participant_id if participant_id
    headers
  end

  def stub_cloudflare_session(session_id: "cf-test-session-001")
    allow_any_instance_of(Cloudflare::Calls)
      .to receive(:create_session)
      .and_return({ "sessionId" => session_id })
  end

  def stub_cloudflare_tracks(
    session_description: { "type" => "answer", "sdp" => "v=0\r\n" },
    tracks: [ { "trackName" => "audio", "mid" => "0" } ],
    requires_immediate_renegotiation: false
  )
    allow_any_instance_of(Cloudflare::Calls)
      .to receive(:add_tracks)
      .and_return({
        "sessionDescription" => session_description,
        "tracks" => tracks,
        "requiresImmediateRenegotiation" => requires_immediate_renegotiation
      })
  end

  def stub_cloudflare_close_tracks(tracks: [])
    allow_any_instance_of(Cloudflare::Calls)
      .to receive(:close_tracks)
      .and_return({ "tracks" => tracks })
  end

  def stub_cloudflare_renegotiate(
    session_description: { "type" => "answer", "sdp" => "v=0\r\n" }
  )
    allow_any_instance_of(Cloudflare::Calls)
      .to receive(:renegotiate)
      .and_return({ "sessionDescription" => session_description })
  end

  def stub_cloudflare_turn(
    ice_servers: [
      {
        "urls" => [ "stun:stun.cloudflare.com:3478", "turn:turn.cloudflare.com:3478" ],
        "username" => "test-user",
        "credential" => "test-credential"
      }
    ]
  )
    allow_any_instance_of(Cloudflare::Turn)
      .to receive(:generate_ice_servers)
      .and_return({ "iceServers" => ice_servers })
  end
end

RSpec.configure do |config|
  config.include WebrtcHelpers, type: :request
end
