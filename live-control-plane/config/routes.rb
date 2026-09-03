Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  namespace :live do
    get "streams/list", to: "streams#list"
    post "streams/create", to: "streams#create"
    get "streams/show", to: "streams#show"
    get "streams/playback_token", to: "streams#playback_token"
    post "streams/change_to_private", to: "streams#change_to_private"
    post "streams/change_to_public", to: "streams#change_to_public"
    post "streams/user_kick", to: "streams#user_kick"
    post "streams/delete_channel", to: "streams#delete_channel"
    post "streams/stop_stream", to: "streams#stop_stream"
  end

  namespace :admin do
    get "streams/list", to: "streams#list"
    post "streams/stop_stream", to: "streams#stop_stream"
    post "streams/destroy", to: "streams#destroy"
  end
end
