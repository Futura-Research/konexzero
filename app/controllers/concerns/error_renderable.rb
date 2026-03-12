module ErrorRenderable
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
    rescue_from ActionController::ParameterMissing, with: :render_bad_request
  end

  private

  # Renders an RFC 7807 Problem Details error response.
  # Always includes `suggestion` and `docs` fields for developer experience.
  def render_error(type:, title:, status:, detail:, suggestion: "")
    status_code = Rack::Utils.status_code(status)
    docs_url = "https://docs.konexzero.com/errors/#{type}"

    body = {
      type: docs_url,
      title: title,
      status: status_code,
      detail: detail,
      suggestion: suggestion.presence || "",
      docs: docs_url
    }

    render json: body, status: status
  end

  def render_not_found(exception)
    render_error(
      type: "not-found",
      title: "Resource not found",
      status: :not_found,
      detail: exception.message,
      suggestion: "Check the resource identifier. Use GET /api/v1/rooms/:room_id to verify the room exists."
    )
  end

  def render_unprocessable(exception)
    render_error(
      type: "validation-failed",
      title: "Validation failed",
      status: :unprocessable_content,
      detail: exception.record.errors.full_messages.to_sentence,
      suggestion: "Check the request body against the API specification at /api/v1/docs/openapi."
    )
  end

  def render_bad_request(exception)
    render_error(
      type: "bad-request",
      title: "Missing parameter",
      status: :bad_request,
      detail: exception.message,
      suggestion: "Include the required parameter. See the API specification at /api/v1/docs/openapi."
    )
  end

  def render_unauthorized(detail: "Invalid or missing API credentials.", suggestion: nil)
    render_error(
      type: "authentication-failed",
      title: "Authentication failed",
      status: :unauthorized,
      detail: detail,
      suggestion: suggestion || "Check your X-App-Id and X-Api-Key headers. " \
                                "You can find these in the KonexZero dashboard."
    )
  end

  def render_forbidden(detail: "You are not a participant in this room.", suggestion: nil)
    render_error(
      type: "forbidden",
      title: "Forbidden",
      status: :forbidden,
      detail: detail,
      suggestion: suggestion || "Call POST /api/v1/rooms/:room_id/join to join the room first."
    )
  end

  def render_conflict(detail: "Resource conflict.", suggestion: nil)
    render_error(
      type: "conflict",
      title: "Conflict",
      status: :conflict,
      detail: detail,
      suggestion: suggestion || "The resource is already in the requested state."
    )
  end

  def render_bad_gateway(exception = nil)
    render_error(
      type: "upstream-error",
      title: "Upstream service error",
      status: :bad_gateway,
      detail: exception&.message || "An upstream service returned an unexpected error.",
      suggestion: "This is a temporary upstream issue. Retry after a short delay."
    )
  end

  def render_too_many_requests(detail: "Upstream rate limit exceeded.", suggestion: nil)
    render_error(
      type: "rate-limited",
      title: "Too Many Requests",
      status: :too_many_requests,
      detail: detail,
      suggestion: suggestion || "Reduce request frequency or contact support for higher limits."
    )
  end
end
