# frozen_string_literal: true

module Ideasbugs
  class AdminBoardsController < DashboardController
    before_action :set_board, only: %i[update destroy]

    def index
      @boards = Board.for_tenant(current_tenant).order(:name)
    end

    def create
      Board.create!(board_params.merge(tenant: current_tenant))
      redirect_to admin_boards_path, status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      render plain: e.message, status: :unprocessable_entity
    end

    def update
      @board.update!(board_params)
      redirect_to admin_boards_path, status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      render plain: e.message, status: :unprocessable_entity
    end

    def destroy
      if @board.destroy
        redirect_to admin_boards_path, status: :see_other
      else
        render plain: @board.errors.full_messages.to_sentence, status: :unprocessable_entity
      end
    end

    private

    def set_board
      @board = find_by_identifier(Board.for_tenant(current_tenant), params[:id])
    end

    def board_params
      params.require(:board).permit(:name, :visibility)
    end
  end
end
