module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :app_id, :room_id, :participant_id

    def connect
      token = request.params[:token]
      reject_unauthorized_connection if token.blank?

      claims = WebrtcTokenService.decode!(token)

      self.app_id         = claims["app_id"]
      self.room_id        = claims["room_id"]
      self.participant_id = claims["participant_id"]
    rescue WebrtcTokenService::InvalidTokenError
      reject_unauthorized_connection
    end
  end
end
