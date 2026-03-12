module Api
  module V1
    class WebhooksController < BaseController
      before_action :set_webhook, only: [ :show, :update, :destroy, :rotate_secret, :test ]

      # GET /api/v1/webhooks
      def index
        webhooks = current_application.webhook_endpoints.order(created_at: :desc)

        render json: {
          data: { webhooks: webhooks.map { |w| serialize_webhook(w) } },
          meta: { timestamp: Time.current.iso8601 }
        }
      end

      # GET /api/v1/webhooks/:id
      def show
        recent_events = @webhook.webhook_events.recent.limit(20)

        render json: {
          data: {
            webhook: serialize_webhook(@webhook),
            recent_events: recent_events.map { |e| serialize_event(e) }
          },
          meta: { timestamp: Time.current.iso8601 }
        }
      end

      # POST /api/v1/webhooks
      def create
        webhook = current_application.webhook_endpoints.build(webhook_params)

        if webhook.save
          render json: {
            data: { webhook: serialize_webhook(webhook).merge(secret: webhook.secret) },
            meta: { timestamp: Time.current.iso8601 }
          }, status: :created
        else
          render_error(
            type: "validation-failed",
            title: "Validation failed",
            status: :unprocessable_content,
            detail: webhook.errors.full_messages.to_sentence,
            suggestion: "Check the url format and subscribed_events values. " \
                        "Valid events: #{WebhookEndpoint::VALID_EVENT_TYPES.join(', ')}."
          )
        end
      end

      # PATCH /api/v1/webhooks/:id
      def update
        if @webhook.update(update_params)
          render json: {
            data: { webhook: serialize_webhook(@webhook) },
            meta: { timestamp: Time.current.iso8601 }
          }
        else
          render_error(
            type: "validation-failed",
            title: "Validation failed",
            status: :unprocessable_content,
            detail: @webhook.errors.full_messages.to_sentence,
            suggestion: "Check the url format and subscribed_events values."
          )
        end
      end

      # DELETE /api/v1/webhooks/:id
      def destroy
        @webhook.destroy!
        head :no_content
      end

      # POST /api/v1/webhooks/:id/rotate_secret
      def rotate_secret
        new_secret = SecureRandom.hex(32)
        @webhook.update!(secret: new_secret)

        render json: {
          data: { webhook: serialize_webhook(@webhook).merge(secret: new_secret) },
          meta: { timestamp: Time.current.iso8601 }
        }
      end

      # POST /api/v1/webhooks/:id/test
      def test
        event = @webhook.webhook_events.create!(
          event_type: "test",
          payload: { test: true, sent_at: Time.current.iso8601 },
          status: "pending"
        )
        WebhookDeliveryWorker.perform_async(event.id)

        render json: {
          data: { event_id: event.id },
          meta: { timestamp: Time.current.iso8601 }
        }, status: :accepted
      end

      private

      def set_webhook
        @webhook = current_application.webhook_endpoints.find(params[:id])
      end

      def webhook_params
        params.permit(:url, :description, subscribed_events: [])
      end

      def update_params
        params.permit(:url, :description, :active, subscribed_events: [])
      end

      def serialize_webhook(webhook)
        {
          id: webhook.id,
          url: webhook.url,
          description: webhook.description,
          subscribed_events: webhook.subscribed_events,
          active: webhook.active,
          created_at: webhook.created_at.iso8601
        }
      end

      def serialize_event(event)
        {
          id: event.id,
          event_type: event.event_type,
          status: event.status,
          response_code: event.response_code,
          attempts: event.attempts,
          created_at: event.created_at.iso8601
        }
      end
    end
  end
end
