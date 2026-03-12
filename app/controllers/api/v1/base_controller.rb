module Api
  module V1
    class BaseController < ActionController::API
      include ErrorRenderable
      include ApiKeyAuthenticatable
    end
  end
end
