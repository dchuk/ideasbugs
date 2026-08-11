# frozen_string_literal: true

module Ideasbugs
  # Serves screenshots to the dashboard under its own authorization, streaming
  # the blob instead of linking Active Storage's public blob URLs. Feedback
  # screenshots can contain anything a user's screen showed, so they must never
  # be reachable without passing the same gate as the dashboard — regardless of
  # how the host app configures (or doesn't configure) blob access.
  class ScreenshotsController < DashboardController
    include ActiveStorage::Streaming if defined?(::ActiveStorage::Streaming)

    def show
      screenshot = Feedback.for_tenant(current_tenant)
                           .find(params[:feedback_id]).screenshots.find(params[:id])

      response.headers['X-Content-Type-Options'] = 'nosniff'
      response.headers['Cache-Control'] = 'private, no-store'
      send_blob_stream screenshot.blob, disposition: 'inline'
    end

    private

    def require_admin
      head :forbidden unless Ideasbugs.admin?(request)
    end
  end
end
