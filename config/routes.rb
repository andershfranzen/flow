Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show"

  namespace :api do
    resource :session, only: [ :show, :create, :destroy ]
    resources :agents, only: [ :index, :create, :update, :destroy ]
    get "me" => "agents#me"
    patch "me" => "agents#update_me"
    post "me/2fa/setup" => "two_factor#setup"
    post "me/2fa/enable" => "two_factor#enable"
    post "me/2fa/disable" => "two_factor#disable"
    get "reports" => "reports#show"

    resources :mailboxes, only: [ :index, :show, :create, :update, :destroy ] do
      member { post :test }
    end

    patch "conversations/bulk" => "conversations#bulk"
    resources :personal_folders, only: [ :index, :create, :update, :destroy ] do
      member do
        post :items, action: :add_items
        delete "items/:conversation_id", action: :remove_item
      end
    end
    resources :conversations, only: [ :index, :show, :create, :update ] do
      resources :messages, only: [ :create, :destroy ]
      member { post :presence }
      member do
        post :merge
        post :follow
        delete :follow, action: :unfollow
      end
    end
    get "stream" => (Rails.env.development? ? "stream_poll#show" : "stream#show")

    resources :customers, only: [ :show, :update ] do
      member { post :merge }
    end
    resources :teams, only: [ :index, :create, :update, :destroy ]
    get "crm/lookup" => "crm#lookup"
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
    patch "workflows/reorder" => "workflows#reorder"
    resources :workflows, only: [ :index, :create, :update, :destroy ]
    resources :plugins, only: [ :index, :update, :destroy ], constraints: { id: /[\w.-]+/ } do
      collection { post :install }
      member { post :upgrade }
    end
    post "oauth/:provider/start" => "oauth#start"
  end

  get "oauth/callback" => "oauth_callbacks#show"
  get "auth/microsoft/start" => "sso#start"
  get "auth/microsoft/callback" => "sso#callback"

  post "mcp" => "mcp#handle"

  # SPA fallback: anything that isn't API/rails/mcp gets the Vue app (H18).
  get "*path", to: "spa#index",
    constraints: ->(req) {
      !req.path.start_with?("/api", "/rails", "/mcp", "/up", "/health", "/oauth", "/auth") &&
        (req.format.nil? || req.format.html? || req.headers["Accept"].to_s.include?("*/*"))
    }
end
