# frozen_string_literal: true

Ideasbugs::Engine.routes.draw do
  # The widget code, served same-origin (see WidgetsController for why).
  get 'widget.js', to: 'widgets#show', as: :widget
  get 'dashboard.css', to: 'widgets#dashboard_stylesheet', as: :dashboard_stylesheet

  # POST goes to SubmissionsController, not to this resource: the widget's write
  # endpoint is public and the rest is staff-only, and only the staff half
  # inherits config.base_controller_class. Sharing one controller would put a
  # host's admin authentication in front of someone filing a report.
  post 'feedbacks', to: 'submissions#create', as: :submissions
  resources :feedbacks, only: %i[index show update destroy] do
    post :merge, on: :member
    delete 'comments/:comment_id', to: 'feedbacks#delete_comment', as: :comment
    # Screenshots stream through the dashboard's own gate, never via public
    # Active Storage blob URLs.
    resources :screenshots, only: :show
  end

  resources :admin_boards, only: %i[index create update destroy]

  resources :boards, only: %i[index show] do
    get 'items/:item_id', to: 'boards#item', as: :item
    post 'items/:item_id/vote', to: 'boards#vote', as: :item_vote
    delete 'items/:item_id/vote', to: 'boards#vote'
    post 'items/:item_id/comments', to: 'boards#comment', as: :item_comments
  end

  root to: 'feedbacks#index'
end
