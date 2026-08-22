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
    assert_equal ['api_song'], Dir.children(@store.songs_root).reject { |entry| entry.start_with?('.') }
    assert File.file?(manifest_path)
    assert File.file?(installed_zip_path)
    assert_equal File.binread(zip_path), File.binread(installed_zip_path)

    installed_manifest = JSON.parse(File.read(manifest_path, encoding: 'UTF-8'))
    assert_equal 'API Song', installed_manifest['song_name']
    assert_equal 42, installed_manifest['song_number']
    assert_equal true, installed_manifest['user_installed']
    assert_guard_unchanged
  end

  test 'create and index preserve an eight chain manifest' do
    data = valid_manifest(
      filename: 'eight_chain_song',
      song_name: 'Eight Chain Song',
      song_number: 45,
      chain_count: 8
    )
    data['holdToPlay']['chain8'] = [0]
    data['linkedAreas']['chain8'] = [[0, 1]]
    zip_path = write_minimal_zip(File.join(@temporary_root, 'uploads', 'eight-chain-song.zip'))

    post_song(data, zip_path)

    assert_response :created
    assert_equal true, parsed_response['ok']

    with_local_api do
      get '/dev/song_imports'
    end

    assert_response :success
    song = parsed_response.fetch('songs').find { |item| item['filename'] == 'eight_chain_song' }
    refute_nil song
    assert_equal 8, song['chain_count']
    assert_equal 48, song.dig('mappings', 'chain8').length
    assert_equal [0], song.dig('holdToPlay', 'chain8')
    assert_equal [[0, 1]], song.dig('linkedAreas', 'chain8')
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

  test 'destroy does not allow a malformed catalog entry to alias a valid sibling' do
    install_song(valid_manifest(filename: 'victim', song_name: 'Victim', song_number: 46))
    malformed_dir = File.join(@store.songs_root, ' victim')
    FileUtils.mkdir_p(malformed_dir)
    File.write(
      File.join(malformed_dir, 'song.json'),
      JSON.generate('song_name' => 'Malformed Alias'),
      mode: 'w',
      encoding: 'UTF-8'
    )
    File.write(File.join(malformed_dir, 'sounds.zip'), 'malformed zip', mode: 'w', encoding: 'UTF-8')

    with_local_api do
      delete '/dev/song_imports/%20victim'
    end

    assert_response :not_found
    assert File.directory?(File.join(@store.songs_root, 'victim'))
    assert File.directory?(malformed_dir)
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
    assert_match(/inline/, response.headers['Content-Disposition'])
    assert_match(/filename="sounds.zip"/, response.headers['Content-Disposition'])
    assert_equal 'binary', response.headers['Content-Transfer-Encoding']
    assert_equal expected_bytes.bytesize.to_s, response.headers['Content-Length']
    assert_nothing_raised { Time.httpdate(response.headers.fetch('Last-Modified')) }
    assert_nil response.headers['ETag']
    assert_equal 'no-cache', response.headers['Cache-Control']
    assert_equal expected_bytes, response.body.b
    assert_guard_unchanged
  end

  test 'zip head returns archive headers and closes the verified descriptor without a body' do
    zip_path = install_song(valid_manifest(filename: 'zip_song', song_name: 'ZIP Song', song_number: 45))
    expected_size = File.size(zip_path)
    original_open_zip = @store.method(:open_zip)
    opened_body = nil
    capturing_open_zip = proc do |filename|
      opened_body = original_open_zip.call(filename)
    end

    @store.stub(:open_zip, capturing_open_zip) do
      with_local_api do
        head '/zip/sounds/zip_song.zip'
      end
    end

    assert_response :success
    assert_equal 'application/zip', response.media_type
    assert_match(/inline/, response.headers['Content-Disposition'])
    assert_match(/filename="sounds.zip"/, response.headers['Content-Disposition'])
    assert_equal 'binary', response.headers['Content-Transfer-Encoding']
    assert_equal expected_size.to_s, response.headers['Content-Length']
    assert_nothing_raised { Time.httpdate(response.headers.fetch('Last-Modified')) }
    assert_nil response.headers['ETag']
    assert_equal 'no-cache', response.headers['Cache-Control']
    assert_empty response.body
    assert opened_body.closed?
    assert_guard_unchanged
  end

  test 'zip range request preserves full 200 response without range headers' do
    zip_path = install_song(valid_manifest(filename: 'zip_song', song_name: 'ZIP Song', song_number: 45))
    expected_bytes = File.binread(zip_path)

    with_local_api do
      get '/zip/sounds/zip_song.zip', headers: { 'Range' => 'bytes=0-9' }
    end

    assert_response :success
    assert_equal expected_bytes, response.body.b
    assert_nil response.headers['Accept-Ranges']
    assert_nil response.headers['Content-Range']
    assert_guard_unchanged
  end

  test 'zip returns not found when the archive is replaced before verified open' do
    install_song(valid_manifest(filename: 'zip_song', song_name: 'ZIP Song', song_number: 45))
    installed_zip = File.join(@store.songs_root, 'zip_song', 'sounds.zip')
    original_zip = File.join(@store.songs_root, 'zip_song', 'original-sounds.zip')
    outside_zip = File.join(@temporary_root, 'outside-replacement.zip')
    File.binwrite(outside_zip, 'outside replacement')
    original_open = File.method(:open)
    replaced = false
    replacing_open = proc do |path, *args, **kwargs, &block|
      if path == installed_zip && !replaced
        File.rename(installed_zip, original_zip)
        File.symlink(outside_zip, installed_zip)
        replaced = true
      end
      original_open.call(path, *args, **kwargs, &block)
    end

    File.stub(:open, replacing_open) do
      with_local_api do
        get '/zip/sounds/zip_song.zip'
      end
    end

    assert replaced
    assert_response :not_found
    assert_empty response.body
    assert_guard_unchanged
  end

  test 'zip returns not found for an unsafe archive symlink' do
    install_song(valid_manifest(filename: 'zip_song', song_name: 'ZIP Song', song_number: 45))
    installed_zip = File.join(@store.songs_root, 'zip_song', 'sounds.zip')
    outside_zip = File.join(@temporary_root, 'outside.zip')
    File.binwrite(outside_zip, 'outside zip')
    File.unlink(installed_zip)
    File.symlink(outside_zip, installed_zip)

    with_local_api do
      get '/zip/sounds/zip_song.zip'
    end

    assert_response :not_found
    assert_empty response.body
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

  def valid_manifest(filename:, song_name:, song_number:, chain_count: nil)
    effective_chain_count = chain_count || 4
    chains = (1..effective_chain_count).map { |number| "chain#{number}" }

    manifest = {
      'schema_version' => 1,
      'song_number' => song_number,
      'song_name' => song_name,
      'bpm' => 120,
      'filename' => filename,
      'mappings' => chains.to_h { |chain| [chain, Array.new(48) { '' }] },
      'holdToPlay' => chains.to_h { |chain| [chain, []] },
      'linkedAreas' => chains.to_h { |chain| [chain, []] }
    }
    manifest['chain_count'] = chain_count if chain_count
    manifest
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
