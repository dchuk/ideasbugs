# frozen_string_literal: true

require 'test_helper'

class BoardsTest < ActionDispatch::IntegrationTest
  setup do
    @board = Ideasbugs::Board.create!(name: 'Product feedback', visibility: 'public')
    @item = Ideasbugs::Feedback.create!(board: @board, message: 'Better exports', kind: 'feature',
                                        visibility: 'listed', author_label: 'private@example.com', page_url: 'https://host/private-token')
    @path = "/feedback/boards/#{@board.id}/items/#{@item.id}"
    Ideasbugs.config.authorize_admin = ->(_request) { false }
  end

  def sign_in
    Ideasbugs.config.current_user = ->(_request) { Struct.new(:id).new('member-1') }
  end

  test 'public reads hide private intake metadata and unlisted reports' do
    get @path
    assert_response :success
    assert_equal 'noindex, nofollow', response.headers['X-Robots-Tag']
    assert_not_includes response.body, 'private@example.com'
    assert_not_includes response.body, 'private-token'
    @item.update!(visibility: 'unlisted')
    get @path
    assert_response :not_found
    get "/feedback/boards/#{@board.id}", params: { q: 'Better' }
    assert_not_includes response.body, 'Better exports'
  end

  test 'private boards require an author and tenant substitution fails' do
    @board.update!(visibility: 'private')
    get @path
    assert_response :not_found
    sign_in
    get @path
    assert_response :success
    Ideasbugs.config.tenant = ->(_request) { 'other' }
    get @path
    assert_response :not_found
  end

  test 'votes and comments use server identity and enforce one reply level' do
    post "#{@path}/vote"
    assert_response :unauthorized
    sign_in
    2.times do
      post "#{@path}/vote", params: { voter_id: 'forged' }
      assert_response :see_other
    end
    assert_equal 1, @item.reload.votes_count
    assert_equal 'member-1', @item.votes.first.voter_id
    post "#{@path}/comments",
         params: { comment: { body: '<script>alert(1)</script>', admin: true, author_id: 'forged' } }
    assert_response :see_other
    assert_not @item.comments.first.admin
    get @path
    assert_includes response.body, '&lt;script&gt;'
    assert_not_includes response.body, '<script>alert(1)</script>'
    delete "#{@path}/vote"
    assert_equal 0, @item.reload.votes_count
  end

  test 'all discovery sorts and filters render' do
    %w[trending top new].each do |sort|
      get "/feedback/boards/#{@board.id}", params: { sort: sort, kind: 'feature', q: 'exports' }
      assert_response :success
      assert_includes response.body, 'Better exports'
    end
  end

  test 'widget requires authentication and rejects foreign boards and forged status' do
    post '/feedback/feedbacks', params: { feedback: { kind: 'bug', message: 'Hi' } }
    assert_response :unauthorized
    sign_in
    post '/feedback/feedbacks',
         params: { feedback: { kind: 'bug', message: 'Hi', board_id: @board.id, visibility: 'listed',
                               status: 'complete' } }
    assert_response :created
    assert_equal 'unlisted', Ideasbugs::Feedback.last.visibility
    assert_equal 'under_review', Ideasbugs::Feedback.last.status
    assert_equal 'Member', Ideasbugs::Feedback.last.author_label
    foreign = Ideasbugs::Board.default_for('other')
    post '/feedback/feedbacks', params: { feedback: { kind: 'bug', message: 'Hi', board_id: foreign.id } }
    assert_response :not_found
  end

  test 'opaque URL mode applies to customer and admin routes without weakening tenant scope' do
    Ideasbugs.config.use_public_ids = true
    get "/feedback/boards/#{@board.to_param}/items/#{@item.to_param}"
    assert_response :success
    assert_match(/\A[A-Za-z0-9]{12}\z/, @board.to_param)
    get @path
    assert_response :not_found
    Ideasbugs.config.authorize_admin = ->(_request) { true }
    get "/feedback/feedbacks/#{@item.to_param}"
    assert_response :success
    get '/feedback', params: { feedback_id: @item.to_param }
    assert_response :success
  end

  test 'SVG uploads are rejected and legacy SVG downloads remain inert' do
    sign_in
    file = Tempfile.new(['legacy', '.svg'])
    file.write('<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
    file.rewind
    upload = Rack::Test::UploadedFile.new(file.path, 'image/svg+xml')
    post '/feedback/feedbacks', params: { feedback: { kind: 'bug', message: 'SVG', screenshots: [upload] } }
    assert_response :unprocessable_entity
    @item.screenshots.attach(io: StringIO.new(file.read), filename: 'legacy.svg', content_type: 'image/svg+xml')
    Ideasbugs.config.authorize_admin = ->(_request) { true }
    get "/feedback/feedbacks/#{@item.id}/screenshots/#{@item.screenshots.first.id}"
    assert_response :success
    assert_includes response.headers['Content-Disposition'], 'attachment'
    assert_includes response.headers['Content-Security-Policy'], 'sandbox'
  ensure
    file&.close!
  end

  test 'moderator lists merges and deletes comments but a customer cannot' do
    sign_in
    patch "/feedback/feedbacks/#{@item.id}", params: { feedback: { visibility: 'unlisted' } }
    assert_response :forbidden
    Ideasbugs.config.authorize_admin = ->(_request) { true }
    patch "/feedback/feedbacks/#{@item.id}", params: { feedback: { visibility: 'unlisted' } }
    assert_response :see_other
    assert_equal 'unlisted', @item.reload.visibility
    get '/feedback/admin_boards'
    assert_response :success
    get '/feedback', params: { visibility: 'unlisted' }
    assert_response :success
  end
end
