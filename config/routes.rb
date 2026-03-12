require "sidekiq/web"

Rails.application.routes.draw do
  # Sidekiq Web UI
  mount Sidekiq::Web => "/sidekiq"

  # API v1 — stateless, API key authenticated
  namespace :api do
    namespace :v1 do
      resource :status, only: :show, controller: :status
      resource :credentials, only: :create

      # OpenAPI spec — public, no auth
      get "docs/openapi", to: "docs#openapi", defaults: { format: :json }

      resources :webhooks, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :rotate_secret
          post :test
        end
      end

      scope "rooms/:room_id" do
        get    "/",            to: "rooms#show",             as: :room
        get    "participants", to: "rooms#participants",     as: :room_participants
        post   "join",         to: "rooms#join",             as: :room_join
        post   "publish",      to: "rooms#publish",          as: :room_publish
        post   "unpublish",    to: "rooms#unpublish",        as: :room_unpublish
        post   "subscribe",    to: "rooms#subscribe",        as: :room_subscribe
        post   "subscribe/answer", to: "rooms#subscribe_answer", as: :room_subscribe_answer
        post   "unsubscribe",  to: "rooms#unsubscribe",      as: :room_unsubscribe
        post   "renegotiate",  to: "rooms#renegotiate",      as: :room_renegotiate
        post   "leave",        to: "rooms#leave",            as: :room_leave

        resources :messages, only: [ :create, :index ]
      end
    end
  end

  # Health checks — unauthenticated
  get "up" => "rails/health#show", as: :rails_health_check
  get "/healthz", to: "health#show"
end
