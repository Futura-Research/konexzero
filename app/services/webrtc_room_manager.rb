class WebrtcRoomManager
  ROOM_TTL      = Integer(ENV.fetch("WEBRTC_ROOM_TTL", 4.hours.to_i))
  SESSION_TTL   = Integer(ENV.fetch("WEBRTC_SESSION_TTL", 4.hours.to_i))
  HEARTBEAT_TTL = Integer(ENV.fetch("WEBRTC_HEARTBEAT_TTL", 90))

  class RoomError < StandardError; end
  class NotInRoomError < RoomError; end

  # @param app_id [String] tenant application identifier (e.g. "app_abc123...")
  # @param redis_pool [ConnectionPool] Redis connection pool (defaults to WEBRTC_REDIS_POOL)
  def initialize(app_id:, redis_pool: WEBRTC_REDIS_POOL)
    @app_id = app_id
    @redis_pool = redis_pool
  end

  # ── Room lifecycle ─────────────────────────────────────────────────

  # Creates or refreshes a room. Idempotent — safe to call multiple times.
  #
  # @param room_id [String] logical room identifier
  # @param type [String] "group" or "1-to-1"
  # @return [Hash] room metadata
  def ensure_room(room_id, type: "group")
    with_redis do |redis|
      key = room_key(room_id)
      redis.hsetnx(key, "created_at", Time.now.utc.iso8601)
      redis.hset(key, "type", type)
      redis.hset(key, "is_active", "true")
      redis.expire(key, ROOM_TTL)
      # Refresh sub-key TTLs so they don't expire before the room key does.
      # expire on a non-existent key is a no-op — safe on first call.
      redis.expire(participants_key(room_id), ROOM_TTL)
      redis.expire(screen_sharer_key(room_id), ROOM_TTL)
      redis.hgetall(key)
    end
  end

  # Returns full room state including all participants, or nil if room doesn't exist.
  #
  # @param room_id [String]
  # @return [Hash, nil] room metadata merged with participants
  def get_room(room_id)
    with_redis do |redis|
      meta = redis.hgetall(room_key(room_id))
      return nil if meta.empty?

      participants = fetch_participants(redis, room_id)
      meta.merge("room_id" => room_id, "participants" => participants)
    end
  end

  # Removes all Redis keys associated with a room.
  #
  # @param room_id [String]
  # @return [void]
  def destroy_room(room_id)
    with_redis { |redis| _destroy_room(redis, room_id) }
  end

  # ── Participant management ─────────────────────────────────────────

  # Adds a participant to the room. Returns the participant data hash.
  #
  # @param room_id [String]
  # @param participant_id [String] caller-supplied unique identifier
  # @param display_name [String] human-readable name (shown in UI)
  # @param session_id [String] Cloudflare SFU session ID
  # @param opts [Hash] optional: avatar_url (String, nil), participant_type ("publisher"|"viewer")
  # @return [Hash] the participant data stored in Redis
  def join_room(room_id, participant_id:, display_name:, session_id:, **opts)
    avatar_url = opts[:avatar_url]
    participant_type = opts.fetch(:participant_type, "publisher")

    participant = {
      "participant_id" => participant_id,
      "display_name" => display_name,
      "avatar_url" => avatar_url,
      "session_id" => session_id,
      "participant_type" => participant_type,
      "joined_at" => Time.now.utc.iso8601,
      "tracks" => {},
      "audio_muted" => true,
      "video_muted" => true,
      "screen_sharing" => false
    }

    with_redis do |redis|
      redis.hset(participants_key(room_id), participant_id, participant.to_json)
      redis.expire(participants_key(room_id), ROOM_TTL)

      redis.hset(session_key(session_id), "room_id", room_id)
      redis.hset(session_key(session_id), "participant_id", participant_id)
      redis.hset(session_key(session_id), "participant_type", participant_type)
      redis.expire(session_key(session_id), SESSION_TTL)

      redis.set(participant_active_room_key(participant_id), room_id, ex: ROOM_TTL)
    end

    participant
  end

  # Removes a participant from the room.
  #
  # Returns the remaining participant count (Integer >= 0) when the participant
  # was present and removed. Returns nil when the participant was not found —
  # callers must distinguish "not found" from "last participant left" (both
  # would otherwise return 0, causing incorrect cleanup in WebSocket disconnect
  # handlers that run after REST /leave has already removed the participant).
  #
  # @param room_id [String]
  # @param participant_id [String]
  # @return [Integer, nil] remaining count, or nil if participant was not found
  def leave_room(room_id, participant_id:)
    with_redis do |redis|
      raw = redis.hget(participants_key(room_id), participant_id)
      return nil unless raw

      participant = JSON.parse(raw)
      redis.hdel(participants_key(room_id), participant_id)
      redis.del(session_key(participant["session_id"])) if participant["session_id"]
      redis.del(participant_active_room_key(participant_id))
      clear_screen_sharer_if_needed(redis, room_id, participant_id)

      remaining = redis.hlen(participants_key(room_id))
      _destroy_room(redis, room_id) if remaining.zero?
      remaining
    end
  end

  # Returns all participants as { participant_id => parsed_hash }.
  #
  # @param room_id [String]
  # @return [Hash]
  def get_participants(room_id)
    with_redis { |redis| fetch_participants(redis, room_id) }
  end

  # Returns a single participant hash or nil.
  #
  # @param room_id [String]
  # @param participant_id [String]
  # @return [Hash, nil]
  def get_participant(room_id, participant_id)
    with_redis do |redis|
      raw = redis.hget(participants_key(room_id), participant_id)
      raw ? JSON.parse(raw) : nil
    end
  end

  # Returns a hash of { participant_id => parsed_hash } for the given IDs in a
  # single HMGET round-trip. Missing participants are excluded from the result.
  #
  # @param room_id [String]
  # @param participant_ids [Array<String>]
  # @return [Hash]
  def get_participants_batch(room_id, participant_ids)
    return {} if participant_ids.empty?

    with_redis do |redis|
      raws = redis.hmget(participants_key(room_id), *participant_ids)
      participant_ids.zip(raws).each_with_object({}) do |(pid, raw), memo|
        memo[pid] = JSON.parse(raw) if raw
      end
    end
  end

  # Returns the number of participants in a room.
  #
  # @param room_id [String]
  # @return [Integer]
  def participant_count(room_id)
    with_redis { |redis| redis.hlen(participants_key(room_id)) }
  end

  # ── Track management ───────────────────────────────────────────────

  # Merges new tracks into a participant's track list. Returns updated tracks hash.
  #
  # @param room_id [String]
  # @param participant_id [String]
  # @param tracks [Array<Hash>] each: { "trackName" => ..., "mid" => ..., "kind" => ... }
  # @return [Hash, nil] updated tracks hash, or nil if participant not found
  def add_tracks(room_id, participant_id, tracks)
    with_redis do |redis|
      participant = fetch_participant(redis, room_id, participant_id)
      return nil unless participant

      existing_tracks = participant["tracks"] || {}
      tracks.each do |track|
        name = track["trackName"] || track[:trackName]
        existing_tracks[name] = {
          "mid" => track["mid"] || track[:mid],
          "kind" => track["kind"] || track[:kind],
          "session_id" => participant["session_id"],
          "published_at" => Time.now.utc.iso8601
        }
      end

      participant["tracks"] = existing_tracks
      redis.hset(participants_key(room_id), participant_id, participant.to_json)
      existing_tracks
    end
  end

  # Removes specified tracks by name from a participant.
  #
  # @param room_id [String]
  # @param participant_id [String]
  # @param track_names [Array<String>]
  # @return [void]
  def remove_tracks(room_id, participant_id, track_names)
    with_redis do |redis|
      participant = fetch_participant(redis, room_id, participant_id)
      return unless participant

      track_names.each { |name| participant["tracks"]&.delete(name) }
      redis.hset(participants_key(room_id), participant_id, participant.to_json)
    end
  end

  # ── Media state ────────────────────────────────────────────────────

  # Updates mute state for a participant. Only updates fields that are not nil.
  #
  # @param room_id [String]
  # @param participant_id [String]
  # @param audio_muted [Boolean, nil]
  # @param video_muted [Boolean, nil]
  # @return [Hash, nil] updated participant hash
  def update_media_state(room_id, participant_id, audio_muted: nil, video_muted: nil)
    with_redis do |redis|
      participant = fetch_participant(redis, room_id, participant_id)
      return nil unless participant

      participant["audio_muted"] = audio_muted unless audio_muted.nil?
      participant["video_muted"] = video_muted unless video_muted.nil?
      redis.hset(participants_key(room_id), participant_id, participant.to_json)
      participant
    end
  end

  # Updates the screen_sharing flag for a participant.
  # Maintains a dedicated Redis key for O(1) screen_sharer lookups.
  #
  # @param room_id [String]
  # @param participant_id [String]
  # @param sharing [Boolean]
  # @return [Hash, nil] updated participant hash
  def update_screen_share_state(room_id, participant_id, sharing:)
    with_redis do |redis|
      participant = fetch_participant(redis, room_id, participant_id)
      return nil unless participant

      participant["screen_sharing"] = sharing
      redis.hset(participants_key(room_id), participant_id, participant.to_json)

      if sharing
        redis.set(screen_sharer_key(room_id), participant_id, ex: ROOM_TTL)
      else
        redis.del(screen_sharer_key(room_id))
      end

      participant
    end
  end

  # Returns the participant_id of whoever is screen-sharing, or nil.
  #
  # @param room_id [String]
  # @return [String, nil]
  def screen_sharer(room_id)
    with_redis { |redis| redis.get(screen_sharer_key(room_id)) }
  end

  # Atomically claims the screen-share lock for participant_id using SETNX.
  # Returns true if the claim succeeded (lock was free or already owned by this
  # participant), false if another participant holds the lock.
  #
  # This prevents TOCTOU races that arise from a separate read-then-write.
  #
  # @param room_id [String]
  # @param participant_id [String]
  # @return [Boolean]
  def try_claim_screen_share(room_id, participant_id)
    with_redis do |redis|
      # SET NX EX: atomically set only if key does not exist.
      claimed = redis.set(screen_sharer_key(room_id), participant_id, nx: true, ex: ROOM_TTL)

      if claimed
        # Update the participant hash screen_sharing flag in the same checkout.
        participant = fetch_participant(redis, room_id, participant_id)
        if participant
          participant["screen_sharing"] = true
          redis.hset(participants_key(room_id), participant_id, participant.to_json)
        end
        true
      else
        current = redis.get(screen_sharer_key(room_id))
        # Allow the same participant to re-claim (idempotent re-publish).
        current == participant_id
      end
    end
  end

  # ── Lookups ────────────────────────────────────────────────────────

  # Returns session metadata hash or nil.
  # Used for reverse lookup: Cloudflare session → room + participant.
  #
  # @param session_id [String] Cloudflare SFU session ID
  # @return [Hash, nil] { "room_id" => ..., "participant_id" => ..., "participant_type" => ... }
  def session_info(session_id)
    with_redis do |redis|
      data = redis.hgetall(session_key(session_id))
      data.empty? ? nil : data
    end
  end

  # Returns the room_id the participant is currently in, or nil.
  #
  # @param participant_id [String]
  # @return [String, nil]
  def participant_active_room(participant_id)
    with_redis { |redis| redis.get(participant_active_room_key(participant_id)) }
  end

  # ── Heartbeat presence ─────────────────────────────────────────────

  # Sets (or refreshes) the heartbeat key for a participant with HEARTBEAT_TTL.
  # Called by RoomChannel on every client heartbeat and on initial subscribe.
  #
  # @param participant_id [String]
  # @return [void]
  def set_heartbeat(participant_id)
    with_redis { |redis| redis.set(heartbeat_key(participant_id), "1", ex: HEARTBEAT_TTL) }
  end

  # Deletes the heartbeat key immediately (belt-and-suspenders on disconnect).
  #
  # @param participant_id [String]
  # @return [void]
  def del_heartbeat(participant_id)
    with_redis { |redis| redis.del(heartbeat_key(participant_id)) }
  end

  # Returns true when the heartbeat key exists (participant is considered alive).
  #
  # @param participant_id [String]
  # @return [Boolean]
  def heartbeat_active?(participant_id)
    with_redis { |redis| redis.exists?(heartbeat_key(participant_id)) }
  end

  # ── Cleanup helpers ────────────────────────────────────────────────

  # Returns participants whose ID is NOT in the online set.
  # Used by the session cleanup worker to detect disconnected participants.
  #
  # @param room_id [String]
  # @param online_ids [Set<String>] set of currently-connected participant IDs
  # @return [Hash] { participant_id => participant_hash } of stale participants
  def find_stale_participants(room_id, online_ids:)
    participants = get_participants(room_id)
    participants.reject { |pid, _| online_ids.include?(pid) }
  end

  # Returns all active room IDs for this tenant via cursor-based SCAN.
  # Safe for production — never blocks Redis with KEYS.
  #
  # @return [Array<String>] room IDs (without the Redis key prefix)
  def all_active_room_ids
    prefix = "kz:#{@app_id}:room:"
    ids = []

    with_redis do |redis|
      cursor = "0"
      loop do
        cursor, keys = redis.scan(cursor, match: "#{prefix}*", count: 100)
        keys.each do |key|
          next if key.include?(":participants") || key.include?(":screen_sharer")

          room_id = key.delete_prefix(prefix)
          ids << room_id
        end
        break if cursor == "0"
      end
    end

    ids
  end

  private

  def with_redis(&block)
    @redis_pool.with(&block)
  end

  # Internal destroy that works with an already-checked-out connection.
  # Prevents nested pool checkout (deadlock risk) when called from leave_room.
  def _destroy_room(redis, room_id)
    participants = fetch_participants(redis, room_id)
    participants.each_value do |p|
      redis.del(session_key(p["session_id"])) if p["session_id"]
      redis.del(participant_active_room_key(p["participant_id"])) if p["participant_id"]
    end
    redis.del(room_key(room_id))
    redis.del(participants_key(room_id))
    redis.del(screen_sharer_key(room_id))
  end

  def fetch_participants(redis, room_id)
    raw = redis.hgetall(participants_key(room_id))
    raw.transform_values { |v| JSON.parse(v) }
  end

  def fetch_participant(redis, room_id, participant_id)
    raw = redis.hget(participants_key(room_id), participant_id)
    raw ? JSON.parse(raw) : nil
  end

  def clear_screen_sharer_if_needed(redis, room_id, participant_id)
    current = redis.get(screen_sharer_key(room_id))
    redis.del(screen_sharer_key(room_id)) if current == participant_id
  end

  # ── Redis key builders (tenant-scoped) ─────────────────────────────

  def room_key(room_id)
    "kz:#{@app_id}:room:#{room_id}"
  end

  def participants_key(room_id)
    "kz:#{@app_id}:room:#{room_id}:participants"
  end

  def session_key(session_id)
    "kz:#{@app_id}:session:#{session_id}"
  end

  def participant_active_room_key(participant_id)
    "kz:#{@app_id}:participant:#{participant_id}:active_room"
  end

  def screen_sharer_key(room_id)
    "kz:#{@app_id}:room:#{room_id}:screen_sharer"
  end

  def heartbeat_key(participant_id)
    "kz:#{@app_id}:participant:#{participant_id}:heartbeat"
  end
end
