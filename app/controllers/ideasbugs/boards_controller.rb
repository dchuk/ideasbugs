# frozen_string_literal: true

module Ideasbugs
  class BoardsController < Ideasbugs.board_controller
    include RequestContext

    layout -> { Ideasbugs.config.board_layout }
    protect_from_forgery with: :exception if superclass == ActionController::Base
    before_action :require_enabled
    before_action :prevent_indexing
    before_action :set_board, except: :index
    before_action :require_author, only: %i[vote comment]
    before_action :set_item, only: %i[item vote comment]

    if respond_to?(:rate_limit) && Ideasbugs.config.rate_limit
      rate_limit(**Ideasbugs.config.rate_limit, only: %i[vote comment],
                                                with: lambda {
                                                  head :too_many_requests
                                                })
    end

    def index
      @boards = accessible_boards.order(:name)
    end

    def show
      @boards = accessible_boards.order(:name)
      @query = params[:q].to_s.strip.first(200)
      @kind = Ideasbugs.config.kinds.include?(params[:kind]) ? params[:kind] : nil
      @sort = %w[trending top new].include?(params[:sort]) ? params[:sort] : 'trending'
      scope = customer_items.where(visibility: 'listed')
      scope = scope.where(kind: @kind) if @kind
      if @query.present?
        scope = scope.where("LOWER(message) LIKE ? ESCAPE '\\'",
                            "%#{Feedback.sanitize_sql_like(@query.downcase)}%")
      end
      scope = sort_items(scope)
      @page = [params[:page].to_i, 1].max
      @items = scope.offset((@page - 1) * 30).limit(31).to_a
      @more = @items.size > 30
      @items = @items.first(30)
    end

    def item
      @voter_page = [params[:voter_page].to_i, 1].max
      @voters = @item.votes.order(:created_at, :id).offset((@voter_page - 1) * 100).limit(101).to_a
      @more_voters = @voters.size > 100
      @voters = @voters.first(100)
      @comment_page = [params[:page].to_i, 1].max
      @comments = @item.comments.where(parent_id: nil).includes(:replies).order(:created_at, :id)
                       .offset((@comment_page - 1) * 30).limit(31).to_a
      @more_comments = @comments.size > 30
      @comments = @comments.first(30)
      @canonical = visible_relation(@item.merged_into)
      @sources = @item.merged_sources.includes(:board).select { |source| visible_relation(source) }
    end

    def vote
      Participation.new(@item).vote(actor_id: current_author.id, label: public_author_label, remove: request.delete?)
      redirect_to board_item_path(@board, @item), status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      render plain: e.message, status: :unprocessable_entity
    end

    def comment
      Participation.new(@item).comment(actor_id: current_author.id, label: public_author_label,
                                       body: params.require(:comment).permit(:body)[:body],
                                       parent_id: params.dig(:comment, :parent_id), admin: Ideasbugs.admin?(request))
      redirect_to board_item_path(@board, @item), status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      render plain: e.message, status: :unprocessable_entity
    end

    private

    def prevent_indexing
      response.headers['X-Robots-Tag'] = 'noindex, nofollow'
      response.headers['Cache-Control'] = 'private, no-store'
    end

    def accessible_boards
      scope = Board.for_tenant(current_tenant)
      current_author ? scope : scope.where(visibility: 'public')
    end

    def set_board
      @board = find_by_identifier(accessible_boards, params[:id] || params[:board_id])
    end

    def customer_items
      @board.feedbacks.where(tenant: current_tenant, visibility: %w[listed merged])
    end

    def set_item
      @item = find_by_identifier(customer_items, params[:item_id])
    end

    def visible_relation(item)
      item if item && item.tenant == current_tenant && %w[listed merged].include?(item.visibility) &&
              (item.board.visibility == 'public' || current_author)
    end

    def sort_items(scope)
      return scope.order(votes_count: :desc, id: :desc) if @sort == 'top'
      return scope.order(created_at: :desc, id: :desc) if @sort == 'new'

      cutoff = Feedback.connection.quote(7.days.ago)
      recent_votes = '(SELECT COUNT(*) FROM ideasbugs_votes ' \
                     'WHERE ideasbugs_votes.feedback_id = ideasbugs_feedbacks.id ' \
                     "AND ideasbugs_votes.created_at >= #{cutoff}) DESC"
      scope.order(Arel.sql(recent_votes))
           .order(votes_count: :desc, id: :desc)
    end
  end
end
