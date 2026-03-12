module Api
  module V1
    # Serves the OpenAPI 3.1 specification as JSON or YAML.
    # Public endpoint — no authentication required.
    class DocsController < ActionController::API
      SPEC_PATH = Rails.root.join("docs/openapi.yaml").freeze

      def openapi
        if request.format.yaml? || params[:format] == "yaml"
          render body: spec_yaml, content_type: "application/x-yaml"
        else
          render json: spec_data
        end
      end

      private

      def spec_data
        @spec_data ||= YAML.safe_load_file(SPEC_PATH, permitted_classes: [])
      end

      def spec_yaml
        @spec_yaml ||= File.read(SPEC_PATH)
      end
    end
  end
end
