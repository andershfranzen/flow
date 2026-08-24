Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    resource :session, only: [ :show, :create, :destroy ]
    resources :agents, only: [ :index, :create, :update, :destroy ]
    get "me" => "agents#me"
    patch "me" => "agents#update_me"
  end

  # SPA fallback: anything that isn't API/rails/mcp gets the Vue app (H18).
  get "*path", to: "spa#index",
    constraints: ->(req) { !req.path.start_with?("/api", "/rails", "/mcp", "/up") && req.format.html? }
end
