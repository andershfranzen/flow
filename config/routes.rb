Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show"

  namespace :api do
    resource :session, only: [ :show, :create, :destroy ]
    resources :agents, only: [ :index, :create, :update, :destroy ]
    get "me" => "agents#me"
    patch "me" => "agents#update_me"

    resources :mailboxes, only: [ :index, :show, :create, :update, :destroy ] do
      member { post :test }
    end

    resources :conversations, only: [ :index, :show, :create, :update ] do
      resources :messages, only: [ :create ]
      post :presence, to: "stream#presence"
      member { post :merge }
    end
    get "stream" => "stream#show"

    resources :customers, only: [ :show, :update ]
    resources :tags, only: [ :index, :create, :update, :destroy ]
    resources :saved_replies, only: [ :index, :create, :update, :destroy ] do
      member { get :render, action: :render_body }
    end
    resources :webhooks, only: [ :index, :create, :update, :destroy ]
    resources :api_tokens, only: [ :index, :create, :destroy ]
    resources :attachments, only: [ :show ]

    get "notifications" => "notifications#index"
    post "notifications/read" => "notifications#read"

    put "drafts" => "drafts#upsert"
    get "drafts" => "drafts#index"
    delete "drafts/:id" => "drafts#destroy"

    resource :org_settings, only: [ :show, :update ]
    post "oauth/:provider/start" => "oauth#start"
  end

  get "oauth/callback" => "oauth_callbacks#show"

  post "mcp" => "mcp#handle"

  # SPA fallback: anything that isn't API/rails/mcp gets the Vue app (H18).
  get "*path", to: "spa#index",
    constraints: ->(req) { !req.path.start_with?("/api", "/rails", "/mcp", "/up", "/health", "/oauth") && req.format.html? }
end
