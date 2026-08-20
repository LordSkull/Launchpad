require 'test_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require 'rack/test'
require 'minitest/mock'
require Rails.root.join('script', 'song_tool').to_s

class LocalSongsApiCharacterizationTest < ActionDispatch::IntegrationTest
  TEST_ROUTES = ActionDispatch::Routing::RouteSet.new
  TEST_ROUTES.draw do
    get    '/dev/song_imports'           => 'local_songs#index'
    post   '/dev/song_imports'           => 'local_songs#create'
    delete '/dev/song_imports/:filename' => 'local_songs#destroy'
    get    '/zip/sounds/:filename.zip'   => 'local_songs#zip'
  end

  def setup
    @temporary_root = Dir.mktmpdir('launchpad-local-songs-api-')
    @store = UserSongStore.new(@temporary_root)
    @guard_path = File.join(@temporary_root, 'outside-store-guard.txt')
    File.write(@guard_path, 'keep', mode: 'w', encoding: 'UTF-8')
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if @temporary_root && File.exist?(@temporary_root)
  end

  def app
    TEST_ROUTES
  end

  test 'index returns the current empty JSON contract' do
    with_local_api do
      get '/dev/song_imports'
    end

    assert_response :success
    assert_equal 'application/json', response.media_type
    assert_equal({ 'ok' => true, 'songs' => [] }, parsed_response)
    assert_guard_unchanged
  end

  test 'index returns an installed user song with generated client fields' do
    install_song(valid_manifest(filename: 'listed_song', song_name: 'Listed Song', song_number: 41))

    with_local_api do
      get '/dev/song_imports'
    end

    assert_response :success
    assert_equal 'application/json', response.media_type

    payload = parsed_response
    assert_equal true, payload['ok']
    assert_kind_of Array, payload['songs']
    song = payload['songs'].find { |item| item['filename'] == 'listed_song' }
    refute_nil song
    assert_equal 'Listed Song', song['song_name']
    assert_equal 120, song['bpm']
    assert_equal 41, song['song_number']
    assert_equal 1, song['schema_version']
    assert_equal true, song['user_installed']
    assert_guard_unchanged
  end

  test 'create installs a valid multipart song package in the temporary store' do
    data = valid_manifest(filename: 'api_song', song_name: 'API Song', song_number: 42)
    zip_path = write_minimal_zip(File.join(@temporary_root, 'uploads', 'api-song.zip'))

    post_song(data, zip_path)

    assert_response :created
    assert_equal 'application/json', response.media_type

    payload = parsed_response
    assert_equal %w[message ok song warnings], payload.keys.sort
    assert_equal true, payload['ok']
    assert_equal 'Song installed successfully.', payload['message']
    assert_equal [], payload['warnings']
    assert_equal %w[bpm filename id manifest_path name zip_path], payload['song'].keys.sort
    assert_equal 'API Song', payload['song']['name']
    assert_equal 120, payload['song']['bpm']
    assert_equal 42, payload['song']['id']
    assert_equal 'api_song', payload['song']['filename']
    assert_equal File.join('user_data', 'songs', 'api_song', 'song.json'), payload['song']['manifest_path']
    assert_equal File.join('user_data', 'songs', 'api_song', 'sounds.zip'), payload['song']['zip_path']

    song_dir = File.join(@store.songs_root, 'api_song')
    manifest_path = File.join(song_dir, 'song.json')
    installed_zip_path = File.join(song_dir, 'sounds.zip')
    assert_equal ['api_song'], Dir.children(@store.songs_root)
    assert File.file?(manifest_path)
    assert File.file?(installed_zip_path)
    assert_equal File.binread(zip_path), File.binread(installed_zip_path)

    installed_manifest = JSON.parse(File.read(manifest_path, encoding: 'UTF-8'))
    assert_equal 'API Song', installed_manifest['song_name']
    assert_equal 42, installed_manifest['song_number']
    assert_equal true, installed_manifest['user_installed']
    assert_guard_unchanged
  end

  test 'create rejects an unsafe filename without installing files' do
    data = valid_manifest(filename: '../evil', song_name: 'Unsafe Song', song_number: 43)
    zip_path = write_minimal_zip(File.join(@temporary_root, 'uploads', 'unsafe-song.zip'))

    post_song(data, zip_path)

    assert_response :unprocessable_entity
    assert_equal 'application/json', response.media_type

    payload = parsed_response
    assert_equal %w[error errors ok warnings], payload.keys.sort
    assert_equal false, payload['ok']
    assert_equal 'Song package is invalid.', payload['error']
    assert payload['errors'].any? { |error| error.include?('filename') }
    assert_equal [], payload['warnings']
    assert_empty Dir.children(@store.songs_root)
    refute File.exist?(File.join(@temporary_root, 'evil'))
    refute File.exist?(File.join(@temporary_root, 'user_data', 'evil'))
    assert_guard_unchanged
  end

  test 'destroy removes an existing song and preserves the store root and siblings' do
    install_song(valid_manifest(filename: 'remove_me', song_name: 'Remove Me', song_number: 44))
    sibling_path = File.join(@store.songs_root, 'keep.txt')
    File.write(sibling_path, 'keep sibling', mode: 'w', encoding: 'UTF-8')

    with_local_api do
      delete '/dev/song_imports/remove_me'
    end

    assert_response :success
    assert_equal 'application/json', response.media_type
    assert_equal(
      {
        'ok' => true,
        'message' => 'Song removed successfully.',
        'song' => { 'name' => 'Remove Me', 'filename' => 'remove_me' }
      },
      parsed_response
    )
    refute File.exist?(File.join(@store.songs_root, 'remove_me'))
    assert File.directory?(@store.songs_root)
    assert_equal 'keep sibling', File.read(sibling_path, encoding: 'UTF-8')
    assert_guard_unchanged
  end

  test 'destroy returns not found for a missing valid filename' do
    with_local_api do
      delete '/dev/song_imports/missing_song'
    end

    assert_response :not_found
    assert_equal 'application/json', response.media_type
    assert_equal({ 'ok' => false, 'error' => 'Song not found.' }, parsed_response)
    assert_empty Dir.children(@store.songs_root)
    assert_guard_unchanged
  end

  test 'zip returns the installed archive byte for byte' do
    zip_path = install_song(valid_manifest(filename: 'zip_song', song_name: 'ZIP Song', song_number: 45))
    expected_bytes = File.binread(zip_path)

    with_local_api do
      get '/zip/sounds/zip_song.zip'
    end

    assert_response :success
    assert_equal 'application/zip', response.media_type
    assert_equal expected_bytes, response.body.b
    assert_guard_unchanged
  end

  test 'zip returns not found when the archive is missing' do
    with_local_api do
      get '/zip/sounds/missing_song.zip'
    end

    assert_response :not_found
    assert_empty response.body
    assert_guard_unchanged
  end

  private

  def with_local_api
    development = ActiveSupport::EnvironmentInquirer.new('development')

    Rails.stub(:env, development) do
      UserSongStore.stub(:new, @store) do
        yield
      end
    end
  end

  def post_song(data, zip_path)
    upload = Rack::Test::UploadedFile.new(zip_path, 'application/zip', true)

    with_local_api do
      post '/dev/song_imports', params: {
        manifest: JSON.generate(data),
        zip: upload
      }
    end
  ensure
    upload.close if upload && upload.respond_to?(:close)
  end

  def valid_manifest(filename:, song_name:, song_number:)
    chains = %w[chain1 chain2 chain3 chain4]

    {
      'schema_version' => 1,
      'song_number' => song_number,
      'song_name' => song_name,
      'bpm' => 120,
      'filename' => filename,
      'mappings' => chains.to_h { |chain| [chain, Array.new(48) { '' }] },
      'holdToPlay' => chains.to_h { |chain| [chain, []] },
      'linkedAreas' => chains.to_h { |chain| [chain, []] }
    }
  end

  def install_song(data)
    input_dir = File.join(@temporary_root, 'inputs', data.fetch('filename'))
    FileUtils.mkdir_p(input_dir)
    manifest_path = File.join(input_dir, 'song.json')
    zip_path = write_minimal_zip(File.join(input_dir, 'sounds.zip'))
    File.write(manifest_path, JSON.generate(data), mode: 'w', encoding: 'UTF-8')

    manifest = SongManifest.new(manifest_path, zip_path).validate!
    raise "Invalid test package: #{manifest.errors.inspect}" unless manifest.valid?

    @store.install!(manifest)
    zip_path
  end

  def write_minimal_zip(path)
    FileUtils.mkdir_p(File.dirname(path))
    eocd = [0x06054b50, 0, 0, 0, 0, 0, 0, 0].pack('VvvvvVVv')
    File.binwrite(path, eocd)
    path
  end

  def parsed_response
    JSON.parse(response.body)
  end

  def assert_guard_unchanged
    assert_equal 'keep', File.read(@guard_path, encoding: 'UTF-8')
  end
end
