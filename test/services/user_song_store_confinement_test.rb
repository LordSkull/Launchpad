require 'test_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require Rails.root.join('script', 'song_store').to_s

class UserSongStoreConfinementTest < ActiveSupport::TestCase
  ManifestStub = Struct.new(:filename, :zip_path, :data, :song_number) do
    def valid?
      true
    end
  end

  def setup
    @temporary_root = Dir.mktmpdir('launchpad-song-store-confinement-')
    @repo_root = File.join(@temporary_root, 'repo')
    @outside_root = File.join(@temporary_root, 'outside')
    FileUtils.mkdir_p([@repo_root, @outside_root])
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if @temporary_root && File.exist?(@temporary_root)
  end

  test 'remove unlinks a terminal song directory symlink without deleting its target' do
    store = UserSongStore.new(@repo_root)
    outside_song = File.join(@outside_root, 'evil_target')
    marker_path = write_marker(outside_song)
    song_link = File.join(store.songs_root, 'evil_song')
    File.symlink(outside_song, song_link)

    assert File.symlink?(song_link)
    assert File.file?(marker_path)
    assert_equal true, store.remove!('evil_song')

    refute File.symlink?(song_link)
    assert File.directory?(outside_song)
    assert_equal 'outside marker', File.read(marker_path, encoding: 'UTF-8')
  end

  test 'a parent songs root symlink is rejected at initialization and by every store operation' do
    outside_songs = File.join(@outside_root, 'outside_songs')
    outside_song = File.join(outside_songs, 'test_song')
    outside_zip = File.join(outside_song, 'sounds.zip')
    marker_path = write_marker(outside_song)
    File.write(outside_zip, 'outside zip', mode: 'w', encoding: 'UTF-8')

    user_data = File.join(@repo_root, 'user_data')
    FileUtils.mkdir_p(user_data)
    songs_link = File.join(user_data, 'songs')
    File.symlink(outside_songs, songs_link)

    initialization_error = assert_raises(RuntimeError) { UserSongStore.new(@repo_root) }

    assert File.symlink?(songs_link)
    assert_match(/Unsafe song storage path/, initialization_error.message)
    assert File.file?(marker_path)

    File.unlink(songs_link)
    FileUtils.mkdir_p(songs_link)
    store = UserSongStore.new(@repo_root)
    Dir.rmdir(songs_link)
    File.symlink(outside_songs, songs_link)

    operations = {
      zip_path: -> { store.zip_path('test_song') },
      remove: -> { store.remove!('test_song') },
      list: -> { store.list },
      installed: -> { store.installed?('test_song') },
      install: -> { store.install!(build_install_manifest) }
    }

    operations.each do |name, operation|
      error = assert_raises(RuntimeError, "Expected #{name} to reject the root symlink", &operation)
      assert_match(/Unsafe song storage path/, error.message)
      assert File.directory?(outside_song)
      assert_equal 'outside marker', File.read(marker_path, encoding: 'UTF-8')
      assert_equal 'outside zip', File.read(outside_zip, encoding: 'UTF-8')
    end

    assert File.directory?(outside_songs)
    assert File.symlink?(songs_link)
  end

  test 'zip path rejects both a symlink file and a symlink song directory' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'test_song')
    FileUtils.mkdir_p(song_dir)
    outside_zip = File.join(@outside_root, 'external.zip')
    File.write(outside_zip, 'external zip', mode: 'w', encoding: 'UTF-8')
    zip_link = File.join(song_dir, 'sounds.zip')
    File.symlink(outside_zip, zip_link)

    zip_error = assert_raises(RuntimeError) { store.zip_path('test_song') }

    assert File.symlink?(zip_link)
    assert_match(/Unsafe song storage path/, zip_error.message)
    assert_equal 'external zip', File.read(outside_zip, encoding: 'UTF-8')

    outside_song = File.join(@outside_root, 'linked_song_target')
    write_song(outside_song, song_name: 'Linked Song', include_zip: true)
    song_link = File.join(store.songs_root, 'linked_song')
    File.symlink(outside_song, song_link)

    song_error = assert_raises(RuntimeError) { store.zip_path('linked_song') }

    assert File.symlink?(song_link)
    assert_match(/Unsafe song storage path/, song_error.message)
    assert File.file?(File.join(outside_song, 'sounds.zip'))
  end

  test 'normal songs remain available while installed rejects a terminal directory symlink' do
    store = UserSongStore.new(@repo_root)
    normal_song = File.join(store.songs_root, 'normal_song')
    write_song(normal_song, song_name: 'Normal Song', include_zip: true)

    outside_song = File.join(@outside_root, 'terminal_target')
    FileUtils.mkdir_p(outside_song)
    File.symlink(outside_song, File.join(store.songs_root, 'linked_song'))

    assert store.installed?('normal_song')
    refute store.installed?('linked_song')
    refute store.installed?('missing_song')
    assert_equal File.join(normal_song, 'sounds.zip'), store.zip_path('normal_song')
    assert_equal ['Normal Song'], store.list.map { |song| song['song_name'] }
  end

  test 'list skips a symlink song directory and a symlink manifest without reading external data' do
    store = UserSongStore.new(@repo_root)
    outside_song = File.join(@outside_root, 'linked_target')
    write_song(outside_song, song_name: 'Linked Song', include_zip: true)
    song_link = File.join(store.songs_root, 'linked_song')
    File.symlink(outside_song, song_link)

    outside_manifest = File.join(@outside_root, 'external_manifest.json')
    File.write(outside_manifest, JSON.generate('song_name' => 'External Manifest'), mode: 'w', encoding: 'UTF-8')
    manifest_link_song = File.join(store.songs_root, 'manifest_link_song')
    FileUtils.mkdir_p(manifest_link_song)
    File.symlink(outside_manifest, File.join(manifest_link_song, 'song.json'))

    songs = store.list

    assert File.symlink?(song_link)
    assert File.symlink?(File.join(manifest_link_song, 'song.json'))
    assert_empty songs
    assert_equal({ 'song_name' => 'External Manifest' }, JSON.parse(File.read(outside_manifest, encoding: 'UTF-8')))
    assert File.file?(File.join(outside_song, 'sounds.zip'))
  end

  test 'list skips missing and invalid manifests but includes a valid manifest without a zip' do
    store = UserSongStore.new(@repo_root)
    FileUtils.mkdir_p(File.join(store.songs_root, 'missing_manifest'))

    invalid_dir = File.join(store.songs_root, 'invalid_manifest')
    FileUtils.mkdir_p(invalid_dir)
    File.write(File.join(invalid_dir, 'song.json'), '{invalid', mode: 'w', encoding: 'UTF-8')

    no_zip_dir = File.join(store.songs_root, 'valid_without_zip')
    write_song(no_zip_dir, song_name: 'No ZIP', include_zip: false)

    songs = store.list

    assert_equal 1, songs.length
    assert_equal 'No ZIP', songs.first['song_name']
    assert_equal 'valid_without_zip', songs.first['filename']
    assert_equal true, songs.first['user_installed']
    refute File.exist?(File.join(no_zip_dir, 'sounds.zip'))
  end

  test 'list currently skips a JSON string rejected by the legacy parser' do
    store = UserSongStore.new(@repo_root)
    scalar_dir = File.join(store.songs_root, 'scalar_manifest')
    FileUtils.mkdir_p(scalar_dir)
    File.write(File.join(scalar_dir, 'song.json'), '"hello"', mode: 'w', encoding: 'UTF-8')

    assert_equal [], store.list
  end

  test 'list currently fails entirely when a manifest contains a JSON array' do
    store = UserSongStore.new(@repo_root)
    array_dir = File.join(store.songs_root, 'array_manifest')
    FileUtils.mkdir_p(array_dir)
    File.write(File.join(array_dir, 'song.json'), '[]', mode: 'w', encoding: 'UTF-8')

    assert_raises(TypeError) { store.list }
  end

  test 'zip path rejects missing songs missing zip files and directories named sounds zip' do
    store = UserSongStore.new(@repo_root)

    missing_song_error = assert_raises(RuntimeError) { store.zip_path('missing_song') }
    assert_match(/was not found/, missing_song_error.message)

    song_dir = File.join(store.songs_root, 'test_song')
    FileUtils.mkdir_p(song_dir)
    missing_zip_error = assert_raises(RuntimeError) { store.zip_path('test_song') }
    assert_match(/was not found/, missing_zip_error.message)

    FileUtils.mkdir_p(File.join(song_dir, 'sounds.zip'))
    directory_error = assert_raises(RuntimeError) { store.zip_path('test_song') }
    assert_match(/was not found/, directory_error.message)
  end

  test 'zip path rejects an unsafe filename through the shared filename validator' do
    store = UserSongStore.new(@repo_root)

    error = assert_raises(RuntimeError) { store.zip_path('../evil') }

    assert_match(/Invalid song filename/, error.message)
  end

  private

  def write_marker(directory)
    FileUtils.mkdir_p(directory)
    marker_path = File.join(directory, 'marker.txt')
    File.write(marker_path, 'outside marker', mode: 'w', encoding: 'UTF-8')
    marker_path
  end

  def write_song(directory, song_name:, include_zip:)
    FileUtils.mkdir_p(directory)
    manifest = {
      'song_name' => song_name,
      'song_number' => 99,
      'filename' => File.basename(directory)
    }
    File.write(File.join(directory, 'song.json'), JSON.generate(manifest), mode: 'w', encoding: 'UTF-8')
    File.write(File.join(directory, 'sounds.zip'), 'zip marker', mode: 'w', encoding: 'UTF-8') if include_zip
  end

  def build_install_manifest
    zip_path = File.join(@outside_root, 'install-input.zip')
    File.write(zip_path, 'install zip', mode: 'w', encoding: 'UTF-8')
    ManifestStub.new(
      'new_song',
      zip_path,
      { 'song_name' => 'New Song', 'filename' => 'new_song' },
      100
    )
  end
end
