module ApiKeyAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_api_key!
    attr_reader :current_credential, :current_application
  end

  private

  def authenticate_api_key!
    app_id = request.headers["X-App-Id"].presence
    api_key = request.headers["X-Api-Key"].presence

    if app_id.nil? || api_key.nil?
      return render_unauthorized(
        detail: "Missing X-App-Id or X-Api-Key header.",
        suggestion: "Include both X-App-Id and X-Api-Key headers in every API request."
      )
    end

    credential = ApiCredential.authenticate(app_id, api_key)

    unless credential
      return render_unauthorized(
        detail: "The provided API credentials are invalid or expired.",
        suggestion: "Verify your API key or generate a new one via POST /api/v1/credentials."
      )
    end

    @current_credential = credential
    @current_application = credential.application

    touch_credential(credential)
  end

  def touch_credential(credential)
    credential.touch_last_used!
  rescue StandardError
    nil
  end
end
