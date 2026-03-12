module Api
  module V1
    class MessagesController < BaseController
      DEFAULT_PAGE_LIMIT = 50
      MAX_PAGE_LIMIT = 100

      before_action :set_room_name

      # POST /api/v1/rooms/:room_id/messages
      # Server-initiated message (system, server-to-room broadcasts, admin API).
      # All message_types including "system" are allowed here.
      # Validation errors are handled by the inherited rescue_from RecordInvalid handler.
      def create
        msg_params = permitted_message_params

        message = Message.create!(
          application:       current_application,
          room_name:         @room_name,
          sender_id:         nil, # server/admin — no participant context
          message_type:      msg_params[:message_type],
          content:           msg_params[:content],
          payload:           msg_params[:payload] || {},
          recipient_id:      msg_params[:recipient_id],
          client_message_id: msg_params[:client_message_id],
          sent_at:           Time.current
        )

        broadcast_message(message)

        render json: { data: { message_id: message.id, sent_at: message.sent_at.iso8601 } },
               status: :created
      end

      # GET /api/v1/rooms/:room_id/messages
      # Returns cursor-paginated broadcast message history (DMs excluded).
      def index
        limit     = [ [ params.fetch(:limit, DEFAULT_PAGE_LIMIT).to_i, 1 ].max, MAX_PAGE_LIMIT ].min
        before_id = params[:before_id].presence

        scope = Message
          .for_room(@room_name)
          .where(application: current_application)
          .broadcast_messages
          .recent_first

        scope = scope.before_cursor(before_id) if before_id

        # Fetch one extra to determine if more pages exist without a separate COUNT query.
        messages = scope.limit(limit + 1).to_a
        has_more = messages.size > limit
        messages = messages.first(limit)

        render json: {
          data: {
            messages: messages.map { |m| serialize_message(m) },
            has_more: has_more,
            next_cursor: has_more ? messages.last&.id : nil
          }
        }
      end

      private

      def set_room_name
        @room_name = params[:room_id]
      end

      def permitted_message_params
        params.permit(
          :message_type, :content, :recipient_id, :client_message_id,
          payload: {}
        )
      end

      def broadcast_message(message)
        target_stream = if message.recipient_id.present?
          "msg:#{current_credential.app_id}:#{@room_name}:dm:#{message.recipient_id}"
        else
          "msg:#{current_credential.app_id}:#{@room_name}:room"
        end

        ActionCable.server.broadcast(target_stream, {
          type:              "message",
          message_id:        message.id,
          sender_id:         message.sender_id,
          message_type:      message.message_type,
          content:           message.content,
          payload:           message.payload.presence,
          recipient_id:      message.recipient_id,
          client_message_id: message.client_message_id,
          sent_at:           message.sent_at.iso8601
        })
      end

      def serialize_message(message)
        {
          message_id:   message.id,
          sender_id:    message.sender_id,
          message_type: message.message_type,
          content:      message.content,
          payload:      message.payload.presence,
          recipient_id: message.recipient_id,
          sent_at:      message.sent_at.iso8601
        }
      end
    end
  end
end
