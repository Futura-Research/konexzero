# KonexZero

**Open-source real-time communication platform** — voice, video & screen sharing APIs powered by Cloudflare WebRTC.

The open-source alternative to Twilio Video, Agora, and 100ms. Self-host it or use [KonexZero Cloud](https://konexzero.com).

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

---

## Features

- **WebRTC Signaling API** — REST API for room management, track publishing/subscribing, SDP negotiation
- **Real-time WebSocket Channels** — Signaling, heartbeat, media state, chat messaging with DM support
- **Built on Cloudflare** — Global Anycast network for media relay (SFU) and TURN/STUN
- **API Key Authentication** — BCrypt-hashed credentials with `X-App-Id` + `X-Api-Key` headers
- **Webhooks** — Event delivery with HMAC-SHA256 signatures, exponential backoff retries
- **Chat Messaging** — Room-scoped broadcast and direct messages via WebSocket + REST
- **Analytics** — Fire-and-forget call event logging (join, leave, publish, screen share, etc.)
- **Session Cleanup** — Automatic stale participant eviction via heartbeat TTL
- **Rate Limiting** — Per-credential and per-IP throttling with RFC 7807 error responses
- **Docker Ready** — `docker compose up` for the full stack (PostgreSQL, Redis, Rails, Sidekiq, AnyCable)

## Stack

| Layer | Technology |
|-------|-----------|
| Backend | Ruby 3.3.8 / Rails 8.1.2 |
| Database | PostgreSQL 16 |
| Cache/State | Redis 7 |
| WebSockets | AnyCable-Go 1.5 + AnyCable-Rails |
| Background Jobs | Sidekiq 7 + sidekiq-cron |
| WebRTC Media | Cloudflare Calls (SFU) + Cloudflare TURN |
| Rate Limiting | Rack::Attack |

## Quick Start

### Prerequisites

- Docker & Docker Compose
- A [Cloudflare Calls](https://developers.cloudflare.com/calls/) account (free tier: 1TB/month)

### 1. Clone & configure

```bash
git clone https://github.com/Futura-Research/konexzero.git
cd konexzero
cp .env.example .env
```

Edit `.env` with your Cloudflare credentials:

```env
CLOUDFLARE_APP_ID=your_app_id
CLOUDFLARE_API_TOKEN=your_api_token
CLOUDFLARE_TURN_KEY_ID=your_turn_key_id
CLOUDFLARE_TURN_KEY_API_TOKEN=your_turn_key_api_token
```

### 2. Start everything

```bash
docker compose up
```

This starts PostgreSQL, Redis, Rails (Puma), Sidekiq, AnyCable RPC, and AnyCable-Go.

### 3. Create an API credential

```bash
docker compose exec web bin/rails console
```

```ruby
app = Application.create!(name: "My App")
credential, raw_secret = ApiCredential.generate_for(app)
puts "App ID: #{credential.app_id}"
puts "Secret: #{raw_secret}"
```

### 4. Join a room

```bash
curl -X POST http://localhost:3000/api/v1/rooms/my-room/join \
  -H "X-App-Id: YOUR_APP_ID" \
  -H "X-Api-Key: YOUR_SECRET" \
  -H "X-Participant-Id: user-1" \
  -H "Content-Type: application/json"
```

## API Reference

### Authentication

All API requests require two headers:
- `X-App-Id` — Your application's credential ID (starts with `app_`)
- `X-Api-Key` — Your raw API secret

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/status` | Health check (DB + Redis) |
| `POST` | `/api/v1/credentials` | Create new API credential |
| `GET` | `/api/v1/rooms/:room_id` | Get room details + participants |
| `GET` | `/api/v1/rooms/:room_id/participants` | List room participants |
| `POST` | `/api/v1/rooms/:room_id/join` | Join a room |
| `POST` | `/api/v1/rooms/:room_id/publish` | Publish audio/video/screen tracks |
| `POST` | `/api/v1/rooms/:room_id/unpublish` | Stop publishing tracks |
| `POST` | `/api/v1/rooms/:room_id/subscribe` | Subscribe to remote tracks |
| `POST` | `/api/v1/rooms/:room_id/subscribe/answer` | Send SDP answer after subscribe |
| `POST` | `/api/v1/rooms/:room_id/unsubscribe` | Unsubscribe from tracks |
| `POST` | `/api/v1/rooms/:room_id/renegotiate` | Renegotiate SDP |
| `POST` | `/api/v1/rooms/:room_id/leave` | Leave a room |
| `GET` | `/api/v1/rooms/:room_id/messages` | Get chat message history |
| `POST` | `/api/v1/rooms/:room_id/messages` | Send a chat message |
| `GET` | `/api/v1/webhooks` | List webhook endpoints |
| `POST` | `/api/v1/webhooks` | Create webhook endpoint |
| `GET` | `/api/v1/webhooks/:id` | Get webhook endpoint details |
| `PUT` | `/api/v1/webhooks/:id` | Update webhook endpoint |
| `DELETE` | `/api/v1/webhooks/:id` | Delete webhook endpoint |
| `POST` | `/api/v1/webhooks/:id/rotate_secret` | Rotate webhook secret |
| `POST` | `/api/v1/webhooks/:id/test` | Send test webhook |

### WebSocket Channels

Connect via WebSocket at `ws://localhost:8080/cable` with a JWT token (returned by the `/join` endpoint).

**RoomChannel** — Real-time signaling:
- `heartbeat` — Keep participant alive
- `media_state_changed` — Broadcast mute/unmute
- `force_mute` — Request peer to mute

**MessageChannel** — Chat messaging:
- `send_message` — Broadcast or direct message
- `typing_started` / `typing_stopped` — Typing indicators

## Development

### Without Docker

```bash
bin/setup    # Install deps, prepare DB
bin/dev      # Start Rails + Sidekiq + AnyCable
```

### Testing

```bash
bundle exec rspec                    # All specs
bundle exec rspec spec/requests/     # API specs only
bin/rubocop                          # Linting
bin/brakeman --no-pager              # Security scan
```

## Architecture

```
Client ──HTTPS──▶ Rails (Puma) ──▶ Cloudflare Calls API (SFU)
                       │
                       ├──▶ Redis (room state, pub/sub)
                       ├──▶ PostgreSQL (rooms, credentials, events)
                       └──▶ Sidekiq (webhooks, analytics, cleanup)

Client ──WSS──▶ AnyCable-Go ──gRPC──▶ AnyCable RPC (Rails)
                                           │
                                           └──▶ Redis pub/sub ──▶ other clients
```

### Key Components

- **`WebrtcRoomManager`** — Redis-backed room state: participants, tracks, screen share locks, heartbeats
- **`Cloudflare::Calls`** — SFU session/track management via Cloudflare's API
- **`Cloudflare::Turn`** — Short-lived ICE server credential generation
- **`RoomChannel`** — WebSocket signaling, heartbeat, media state changes
- **`MessageChannel`** — Chat with broadcast + direct messaging
- **`WebrtcSessionCleanupWorker`** — Evicts stale participants based on heartbeat TTL

## Migrating from Twilio Video

See [docs/migrating-from-twilio.md](docs/migrating-from-twilio.md) for a step-by-step migration guide.

## KonexZero Cloud

Don't want to self-host? [KonexZero Cloud](https://konexzero.com) offers:

- Managed infrastructure on Cloudflare's global network
- Developer dashboard with API key management
- Real-time analytics and usage monitoring
- Webhook management UI
- 99.9% SLA, priority support
- Free tier: 10,000 participant-minutes/month

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[Apache License 2.0](LICENSE)
