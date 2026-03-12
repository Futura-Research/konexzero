module WebrtcConcern
  extend ActiveSupport::Concern

  private

  # ── Service accessors ─────────────────────────────────────────────

  def room_manager
    @room_manager ||= WebrtcRoomManager.new(app_id: current_credential.app_id)
  end

  def cf_calls
    @cf_calls ||= Cloudflare::Calls.new
  end

  def cf_turn
    @cf_turn ||= Cloudflare::Turn.new
  end

  # ── Request helpers ───────────────────────────────────────────────

  # The raw room name from the URL — NOT namespace-prefixed.
  # WebrtcRoomManager handles tenant scoping internally via app_id.
  def room_name
    params[:room_id]
  end

  # Caller-supplied participant identifier from the X-Participant-Id header.
  def current_participant_id
    request.headers["X-Participant-Id"]
  end

  # Fetches the current participant from Redis, or nil if not present.
  def current_participant
    return nil if current_participant_id.blank?

    @current_participant ||= room_manager.get_participant(room_name, current_participant_id)
  end

  # Before-action guard: returns 403 if the caller is not in the room.
  def validate_participant!
    render_forbidden unless current_participant
  end

  # ── Sanitisation ─────────────────────────────────────────────────

  # Strips the internal session_id from a single participant hash.
  def sanitize_participant(hash)
    hash.except("session_id")
  end

  # Strips session_id from every participant in a room hash.
  def sanitize_room(hash)
    return hash unless hash["participants"].is_a?(Hash)

    hash.merge(
      "participants" => hash["participants"].transform_values { |p| sanitize_participant(p) }
    )
  end

  # ── Response helpers ──────────────────────────────────────────────

  def render_meta
    { timestamp: Time.current.iso8601 }
  end

  # ── Broadcast helpers ─────────────────────────────────────────────

  # Publishes a payload to every connected subscriber in the room.
  # Stream key is tenant-scoped: "webrtc:{app_id}:{room_id}:signals"
  def broadcast_to_room(room_id, payload)
    ActionCable.server.broadcast(
      "webrtc:#{current_credential.app_id}:#{room_id}:signals",
      payload
    )
  end

  # ── Analytics helpers ─────────────────────────────────────────────

  # Enqueues an async analytics event. Never raises — analytics must not block signaling.
  def log_event(event_type, room_name, participant_id: nil, payload: {})
    CallEventLogger.log(
      application_id: current_application.id,
      event_type:,
      room_name:,
      participant_id:,
      payload:
    )
  rescue StandardError => e
    Rails.logger.error("[WebrtcConcern#log_event] #{e.message}")
  end

  # ── Webhook helpers ──────────────────────────────────────────────

  def dispatch_webhook(event_type, room_name, payload = {})
    WebhookDispatchService.dispatch(
      application: current_application,
      event_type: event_type,
      payload: payload.merge(room_id: room_name, application_id: current_application.id)
    )
  rescue StandardError => e
    Rails.logger.error("[WebrtcConcern#dispatch_webhook] #{e.message}")
  end

  # ── Cloudflare error mapping ──────────────────────────────────────

  # Maps Cloudflare::HttpClient error classes to RFC 7807 responses.
  # Call this in rescue blocks: `rescue Cloudflare::HttpClient::ApiError => e; handle_cf_error(e); end`
  def handle_cf_error(error)
    case error
    when Cloudflare::HttpClient::RateLimitError
      render_too_many_requests(
        detail: "Upstream rate limit exceeded. Please try again shortly.",
        suggestion: "Reduce request frequency. Signaling endpoints share a rate limit."
      )
    when Cloudflare::HttpClient::SessionNotFoundError
      render_not_found(error)
    else
      render_bad_gateway(error)
    end
  end
end
