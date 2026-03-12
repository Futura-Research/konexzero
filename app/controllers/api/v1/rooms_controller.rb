module Api
  module V1
    class RoomsController < BaseController
      include WebrtcConcern

      before_action :validate_participant!, except: [ :join ]

      # GET /api/v1/rooms/:room_id
      def show
        room = room_manager.get_room(room_name)
        return render_not_found(ActiveRecord::RecordNotFound.new("Room '#{room_name}' not found")) unless room

        render json: {
          data: sanitize_room(room),
          meta: render_meta
        }
      end

      # GET /api/v1/rooms/:room_id/participants
      def participants
        parts = room_manager.get_participants(room_name)

        render json: {
          data: {
            participants: parts.transform_values { |p| sanitize_participant(p) },
            count: parts.size
          },
          meta: render_meta
        }
      end

      # POST /api/v1/rooms/:room_id/join
      def join
        if current_participant_id.blank?
          return render_bad_request(
            ActionController::ParameterMissing.new("X-Participant-Id")
          )
        end

        room_type = params.fetch(:room_type, "group")

        db_room = Room.find_or_create_for(
          application: current_application,
          name: room_name
        )
        room_manager.ensure_room(room_name, type: room_type)

        cf_session = cf_calls.create_session
        session_id = cf_session["sessionId"]

        participant = room_manager.join_room(
          room_name,
          participant_id: current_participant_id,
          display_name: params.require(:display_name),
          session_id: session_id,
          avatar_url: params[:avatar_url],
          participant_type: params.fetch(:participant_type, "publisher")
        )

        ice_servers = begin
          Array.wrap(cf_turn.generate_ice_servers["iceServers"])
        rescue Cloudflare::HttpClient::ApiError
          []
        end

        ws_token = WebrtcTokenService.generate(
          app_id:         current_credential.app_id,
          room_id:        room_name,
          participant_id: current_participant_id
        )

        broadcast_to_room(room_name, {
          type:        "participant_joined",
          participant: sanitize_participant(participant),
          timestamp:   Time.current.iso8601
        })

        log_event("participant.joined", room_name, participant_id: current_participant_id)

        dispatch_webhook("participant.joined", room_name,
                         participant_id: current_participant_id,
                         display_name: params.require(:display_name))
        if db_room.previously_new_record?
          dispatch_webhook("room.started", room_name, started_at: db_room.created_at.iso8601)
        end

        render json: {
          data: {
            room: {
              room_id: room_name,
              type: db_room.metadata&.fetch("type", room_type) || room_type,
              is_active: db_room.active?,
              created_at: db_room.created_at.iso8601
            },
            participant: sanitize_participant(participant),
            ice_servers: ice_servers,
            ws_token: ws_token
          },
          meta: render_meta
        }
      rescue Cloudflare::HttpClient::ApiError => e
        handle_cf_error(e)
      end

      # POST /api/v1/rooms/:room_id/publish
      def publish
        tracks_param    = params.require(:tracks)
        sdp_param       = params.require(:session_description)
        session_id      = current_participant["session_id"]
        screen_track    = tracks_param.any? { |t| screen_track?(t) }

        if screen_track
          unless room_manager.try_claim_screen_share(room_name, current_participant_id)
            return render_conflict(
              detail: "Another participant is already sharing their screen.",
              suggestion: "Wait for them to stop sharing before starting your own."
            )
          end
        end

        cf_tracks = tracks_param.map do |t|
          { location: "local", trackName: t[:track_name], mid: t[:mid] }
        end

        result = cf_calls.add_tracks(
          session_id,
          tracks: cf_tracks,
          session_description: { sdp: sdp_param[:sdp], type: sdp_param[:type] }
        )

        # Build an index for O(1) kind lookup when matching CF response tracks.
        input_by_name = tracks_param.index_by { |t| t[:track_name] }

        stored_tracks = (result["tracks"] || []).map do |t|
          input = input_by_name[t["trackName"]]
          {
            "trackName" => t["trackName"],
            "mid" => t["mid"],
            "kind" => input&.dig(:kind) || t["kind"]
          }
        end

        room_manager.add_tracks(room_name, current_participant_id, stored_tracks)

        broadcast_to_room(room_name, {
          type:           "track_published",
          participant_id: current_participant_id,
          tracks:         stored_tracks.map { |t| { track_name: t["trackName"], kind: t["kind"] } },
          timestamp:      Time.current.iso8601
        })

        event_type = screen_track ? "screenshare.started" : "track.published"
        log_event(event_type, room_name, participant_id: current_participant_id)

        sd = result["sessionDescription"] || {}
        render json: {
          data: {
            session_description: { type: sd["type"], sdp: sd["sdp"] },
            tracks: stored_tracks.map { |t| { track_name: t["trackName"], mid: t["mid"], kind: t["kind"] } },
            requires_immediate_renegotiation: result["requiresImmediateRenegotiation"] || false
          },
          meta: render_meta
        }
      rescue Cloudflare::HttpClient::ApiError => e
        handle_cf_error(e)
      end

      # POST /api/v1/rooms/:room_id/unpublish
      def unpublish
        track_names = Array.wrap(params.require(:track_names))
        session_id  = current_participant["session_id"]
        tracks_hash = current_participant["tracks"] || {}

        if track_names == [ "*" ]
          mids = tracks_hash.values.filter_map { |t| t["mid"] }
        else
          missing = track_names.reject { |n| tracks_hash.key?(n) }
          return render_not_found(ActiveRecord::RecordNotFound.new("Tracks not found: #{missing.join(', ')}")) if missing.any?

          mids = track_names.filter_map { |n| tracks_hash.dig(n, "mid") }
        end

        cf_error = nil
        begin
          cf_calls.close_tracks(session_id, track_mids: mids)
        rescue Cloudflare::HttpClient::ApiError => e
          cf_error = e
          Rails.logger.warn("[RoomsController#unpublish] CF track close failed for " \
                            "#{current_participant_id}: #{e.message} — cleaning Redis anyway")
        end

        close_all = track_names == [ "*" ]
        names_to_remove = close_all ? tracks_hash.keys : track_names
        room_manager.remove_tracks(room_name, current_participant_id, names_to_remove)

        if names_to_remove.any? { |n| n.to_s.include?("screen") }
          room_manager.update_screen_share_state(room_name, current_participant_id, sharing: false)
        end

        broadcast_to_room(room_name, {
          type:           "track_unpublished",
          participant_id: current_participant_id,
          track_names:    names_to_remove,
          timestamp:      Time.current.iso8601
        })

        screen_unpublished = names_to_remove.any? { |n| n.to_s.include?("screen") }
        log_event(
          screen_unpublished ? "screenshare.stopped" : "track.unpublished",
          room_name,
          participant_id: current_participant_id
        )

        return handle_cf_error(cf_error) if cf_error

        render json: {
          data: { closed_tracks: names_to_remove },
          meta: render_meta
        }
      end

      # POST /api/v1/rooms/:room_id/subscribe
      def subscribe
        subscriptions = params.require(:subscriptions)
        session_id = current_participant["session_id"]
        remote_tracks = []

        # Batch-fetch all referenced remote participants in one HMGET round-trip
        # instead of one HGET per subscription.
        remote_pids = subscriptions.map { |sub| sub[:participant_id] }.uniq
        remote_participants = room_manager.get_participants_batch(room_name, remote_pids)

        subscriptions.each do |sub|
          remote_pid  = sub[:participant_id]
          track_names = Array.wrap(sub[:track_names])

          remote_participant = remote_participants[remote_pid]
          unless remote_participant
            return render_not_found(
              ActiveRecord::RecordNotFound.new("Participant '#{remote_pid}' not found in room")
            )
          end

          remote_session_id  = remote_participant["session_id"]
          remote_tracks_hash = remote_participant["tracks"] || {}

          track_names.each do |track_name|
            unless remote_tracks_hash.key?(track_name)
              return render_not_found(
                ActiveRecord::RecordNotFound.new(
                  "Track '#{track_name}' not published by participant '#{remote_pid}'"
                )
              )
            end

            remote_tracks << {
              location: "remote",
              sessionId: remote_session_id,
              trackName: track_name
            }
          end
        end

        result = cf_calls.add_tracks(session_id, tracks: remote_tracks)

        sd = result["sessionDescription"] || {}
        render json: {
          data: {
            session_description: { type: sd["type"], sdp: sd["sdp"] },
            tracks: (result["tracks"] || []).map { |t| { track_name: t["trackName"], mid: t["mid"] } }
          },
          meta: render_meta
        }
      rescue Cloudflare::HttpClient::ApiError => e
        handle_cf_error(e)
      end

      # POST /api/v1/rooms/:room_id/subscribe/answer
      def subscribe_answer
        sdp_param  = params.require(:session_description)
        session_id = current_participant["session_id"]

        cf_calls.renegotiate(
          session_id,
          session_description: { sdp: sdp_param[:sdp], type: sdp_param[:type] }
        )

        render json: { data: {}, meta: render_meta }
      rescue Cloudflare::HttpClient::ApiError => e
        handle_cf_error(e)
      end

      # POST /api/v1/rooms/:room_id/unsubscribe
      def unsubscribe
        track_names = Array.wrap(params.require(:track_names))
        session_id  = current_participant["session_id"]
        tracks_hash = current_participant["tracks"] || {}

        mids = track_names.filter_map { |n| tracks_hash.dig(n, "mid") }

        cf_calls.close_tracks(session_id, track_mids: mids)
        room_manager.remove_tracks(room_name, current_participant_id, track_names)

        render json: {
          data: { closed_tracks: track_names },
          meta: render_meta
        }
      rescue Cloudflare::HttpClient::ApiError => e
        handle_cf_error(e)
      end

      # POST /api/v1/rooms/:room_id/renegotiate
      def renegotiate
        sdp_param  = params.require(:session_description)
        session_id = current_participant["session_id"]

        result = cf_calls.renegotiate(
          session_id,
          session_description: { sdp: sdp_param[:sdp], type: sdp_param[:type] }
        )

        sd = result["sessionDescription"] || {}
        render json: {
          data: {
            session_description: { type: sd["type"], sdp: sd["sdp"] }
          },
          meta: render_meta
        }
      rescue Cloudflare::HttpClient::ApiError => e
        handle_cf_error(e)
      end

      # POST /api/v1/rooms/:room_id/leave
      def leave
        participant = current_participant
        session_id  = participant["session_id"]

        begin
          cf_calls.close_tracks(session_id, track_mids: [ "*" ], force: true)
        rescue Cloudflare::HttpClient::ApiError => e
          Rails.logger.warn("[RoomsController#leave] CF track close failed for " \
                            "#{current_participant_id}: #{e.message}")
        end

        remaining = room_manager.leave_room(room_name, participant_id: current_participant_id)

        if remaining.zero?
          db_room = Room.find_active_for(app_id: current_credential.app_id, name: room_name)
          db_room&.end_room!
          log_event("room.ended", room_name)
        end

        broadcast_to_room(room_name, {
          type:                   "participant_left",
          participant_id:         current_participant_id,
          remaining_participants: remaining,
          timestamp:              Time.current.iso8601
        })

        log_event("participant.left", room_name, participant_id: current_participant_id)

        dispatch_webhook("participant.left", room_name,
                         participant_id: current_participant_id,
                         reason: "voluntary")
        if remaining.zero?
          dispatch_webhook("room.ended", room_name, ended_at: Time.current.iso8601)
        end

        render json: {
          data: { remaining_participants: remaining },
          meta: render_meta
        }
      end

      private

      def screen_track?(track)
        name = track[:track_name] || track["track_name"] || ""
        name.to_s.include?("screen")
      end
    end
  end
end
