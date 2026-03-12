module Api
  module V1
    class StatusController < BaseController
      def show
        render json: {
          data: {
            application: current_application.name,
            credential_app_id: current_credential.app_id
          },
          meta: {
            timestamp: Time.current.iso8601
          }
        }
      end
    end
  end
end
