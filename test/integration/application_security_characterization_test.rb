require 'test_helper'
require 'json'

class ApplicationSecurityCharacterizationTest < ActionDispatch::IntegrationTest
  def test_home_remains_available
    get '/'

    assert_response :success
    assert_includes response.body, 'Online Launchpad'
  end

  def test_unauthenticated_create_song_does_not_write_to_the_database
    assert_no_difference('Song.count') do
      post '/create_song', params: {
        song_data: serialized_notes,
        songNum: 7,
        name: 'Unauthenticated Song'
      }
    end

    assert_response :success
    assert_equal 'nil', parsed_response['data']
  end

  private

  def parsed_response
    JSON.parse(response.body)
  end

  def serialized_notes(note = 48)
    JSON.generate([{ note: note, beat: 0, length: 1 }])
  end
end

class LegacyCreateSongSessionCharacterizationTest < ActionController::TestCase
  tests SongController

  def test_non_nil_user_session_create_song_creates_a_legacy_database_record
    @request.session[:user_id] = 1
    song_data = serialized_notes

    assert_difference('Song.count', 1) do
      post :create, params: {
        song_data: song_data,
        songNum: 7,
        name: 'Legacy Database Song'
      }
    end

    assert_response :success
    created_song = Song.find(parsed_response['data'])
    assert_equal created_song.id, parsed_response['data']
    assert_equal 'Legacy Database Song', created_song.name
    assert_equal 7, created_song.song_number
    assert_equal song_data, created_song.song_data
  end

  private

  def parsed_response
    JSON.parse(response.body)
  end

  def serialized_notes
    JSON.generate([{ note: 48, beat: 0, length: 1 }])
  end
end
