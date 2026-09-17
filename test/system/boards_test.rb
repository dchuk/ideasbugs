# frozen_string_literal: true

require 'test_helper'

class BoardsSystemTest < ApplicationSystemTestCase
  setup do
    Ideasbugs.config.current_user = ->(_request) { Struct.new(:id).new('member') }
    Ideasbugs.config.authorize_admin = ->(_request) { true }
    @board = Ideasbugs::Board.create!(name: 'Feature requests', visibility: 'private')
    @feedback = Ideasbugs::Feedback.create!(board: @board, message: 'Export sharper maps', kind: 'feature',
                                            visibility: 'listed')
  end

  test 'customer can discover vote and discuss a request at narrow width' do
    page.driver.browser.manage.window.resize_to(480, 900)
    visit "/feedback/boards/#{@board.id}"
    assert_text 'Feature requests'
    click_link 'Export sharper maps'
    click_button 'Vote for this'
    assert_text '1 vote'
    fill_in 'Your comment', with: 'Useful for presentations'
    click_button 'Post comment'
    assert_text 'Useful for presentations'
    assert_text 'Administrator'
    click_button 'Remove my vote'
    assert_text '0 votes'
  end
end
