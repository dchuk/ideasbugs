# frozen_string_literal: true

module Ideasbugs
  class FeedbacksController < DashboardController
    PER_PAGE = 50

    # The widget posts here; everything else is the triage dashboard.
    before_action :set_feedback, only: %i[show update destroy merge delete_comment]

    def index
      @status = Feedback::STATUSES.include?(params[:status]) ? params[:status] : 'under_review'
      @visibility = %w[unlisted listed merged all].include?(params[:visibility]) ? params[:visibility] : 'all'
      @boards = Board.for_tenant(current_tenant).order(:name)
      @kind = Ideasbugs.config.kinds.map(&:to_s).include?(params[:kind]) ? params[:kind] : nil
      @query = params[:q].to_s.strip.presence
      @counts = tenant_scope.group(:status).count

      scope = tenant_scope.where(status: @status)
      scope = scope.where(visibility: @visibility) unless @visibility == 'all'
      scope = scope.where(board_id: @boards.find(params[:board_id]).id) if params[:board_id].present?
      scope = scope.where(kind: @kind) if @kind
      scope = search(scope) if @query
      @page = [params[:page].to_i, 1].max
      @feedbacks = scope.newest_first.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
      @more = @feedbacks.size > PER_PAGE
      @feedbacks = @feedbacks.first(PER_PAGE)

      @selected_feedback = find_by_identifier(tenant_scope, params[:feedback_id]) if params[:feedback_id].present?

      # Only surface the Section column when it can carry information: the host
      # configured sections, or some record already has one (e.g. sections were
      # configured historically). Otherwise it's a permanently blank column.
      @show_section = @feedbacks.any? { |f| f.section.present? }
    end

    def show; end

    def update
      @feedback.with_lock do
        attributes = params.require(:feedback).permit(:status, :visibility)
        allowed_visibility = %w[listed unlisted].include?(attributes[:visibility])
        if attributes[:visibility] && (!allowed_visibility || @feedback.visibility == 'merged')
          return render plain: 'Use the merge action for merged feedback', status: :unprocessable_entity
        end

        @feedback.update!(attributes)
      end
      redirect_back fallback_location: feedback_path(@feedback), status: :see_other
    end

    def destroy
      @feedback.with_lock { @feedback.destroy! }
      redirect_to root_path, status: :see_other
    end

    def merge
      target = find_by_identifier(tenant_scope, params.require(:target_id))
      Merge.call(source: @feedback, target: target)
      redirect_to feedback_path(target), status: :see_other
    rescue ArgumentError => e
      render plain: e.message, status: :unprocessable_entity
    end

    def delete_comment
      Participation.new(@feedback).delete_comment(params[:comment_id])
      redirect_to feedback_path(@feedback), status: :see_other
    end

    private

    def set_feedback
      @feedback = find_by_identifier(tenant_scope, params[:id])
    end

    # Case-insensitive match on the free-text columns. LOWER() keeps it
    # portable across SQLite/PostgreSQL/MySQL, and the explicit ESCAPE makes
    # the sanitized backslash escapes work on SQLite, which has no default
    # LIKE escape character.
    def search(scope)
      pattern = "%#{Feedback.sanitize_sql_like(@query.downcase)}%"
      scope.where(
        "LOWER(message) LIKE :q ESCAPE '\\' OR LOWER(COALESCE(author_label, '')) LIKE :q ESCAPE '\\' " \
        "OR LOWER(COALESCE(section, '')) LIKE :q ESCAPE '\\'",
        q: pattern
      )
    end
  end
end
