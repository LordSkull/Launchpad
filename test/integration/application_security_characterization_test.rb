require 'test_helper'

class ApplicationSecurityCharacterizationTest < ActionDispatch::IntegrationTest
  def test_home_remains_available
    get '/'

    assert_response :success
    assert_includes response.body, 'Online Launchpad'
  end

  def test_legacy_create_song_route_is_not_available
    assert_no_difference('Song.count') do
      assert_raises(ActionController::RoutingError) do
        post '/create_song', params: {
          song_data: '[{"note":48,"beat":0,"length":1}]',
          songNum: 7,
          name: 'Legacy Song'
        }
      end
    end
  end

  def test_legacy_view_all_songs_route_is_not_available
    assert_raises(ActionController::RoutingError) do
      post '/view_all_songs'
    end
  end

  def test_legacy_login_route_is_not_available
    assert_raises(ActionController::RoutingError) do
      post '/login'
    end
  end

  def test_legacy_logout_route_is_not_available
    assert_raises(ActionController::RoutingError) do
      get '/logout'
    end
  end
end
