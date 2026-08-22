require 'test_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require 'minitest/mock'
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
      open_zip: -> { store.open_zip('test_song') },
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

  test 'initialization rejects a symlink ancestor before creating the songs root through it' do
    outside_user_data = File.join(@outside_root, 'outside_user_data')
    FileUtils.mkdir_p(outside_user_data)
    user_data_link = File.join(@repo_root, 'user_data')

    begin
      File.symlink(outside_user_data, user_data_link)
    rescue NotImplementedError, Errno::EACCES, Errno::EPERM
      skip 'Symlink creation is unavailable on this platform'
    end

    error = assert_raises(RuntimeError) { UserSongStore.new(@repo_root) }

    assert_match(/Unsafe song storage path/, error.message)
    refute File.exist?(File.join(outside_user_data, 'songs'))
  end

  test 'zip access rejects both a symlink file and a symlink song directory' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'test_song')
    FileUtils.mkdir_p(song_dir)
    outside_zip = File.join(@outside_root, 'external.zip')
    File.write(outside_zip, 'external zip', mode: 'w', encoding: 'UTF-8')
    zip_link = File.join(song_dir, 'sounds.zip')
    File.symlink(outside_zip, zip_link)

    zip_error = assert_raises(RuntimeError) { store.zip_path('test_song') }
    open_zip_error = assert_raises(RuntimeError) { store.open_zip('test_song') }

    assert File.symlink?(zip_link)
    assert_match(/Unsafe song storage path/, zip_error.message)
    assert_match(/Unsafe song storage path/, open_zip_error.message)
    assert_equal 'external zip', File.read(outside_zip, encoding: 'UTF-8')

    outside_song = File.join(@outside_root, 'linked_song_target')
    write_song(outside_song, song_name: 'Linked Song', include_zip: true)
    song_link = File.join(store.songs_root, 'linked_song')
    File.symlink(outside_song, song_link)

    song_error = assert_raises(RuntimeError) { store.zip_path('linked_song') }
    open_song_error = assert_raises(RuntimeError) { store.open_zip('linked_song') }

    assert File.symlink?(song_link)
    assert_match(/Unsafe song storage path/, song_error.message)
    assert_match(/Unsafe song storage path/, open_song_error.message)
    assert File.file?(File.join(outside_song, 'sounds.zip'))
  end

  test 'open zip streams bounded chunks from a verified descriptor and closes it' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'test_song')
    write_song(song_dir, song_name: 'Test Song', include_zip: true)
    expected_bytes = (0..255).to_a.pack('C*') * 300
    File.binwrite(File.join(song_dir, 'sounds.zip'), expected_bytes)

    verified_zip = store.open_zip('test_song')
    chunks = []

    assert_equal expected_bytes.bytesize, verified_zip.size
    refute_respond_to verified_zip, :to_path
    refute verified_zip.closed?
    verified_zip.each { |chunk| chunks << chunk }

    assert_equal expected_bytes, chunks.join
    assert chunks.all? { |chunk| chunk.bytesize <= 64 * 1024 }
    assert verified_zip.closed?
    verified_zip.close
    verified_zip.close
    assert verified_zip.closed?
  end

  test 'open zip closes when response enumeration raises' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'test_song')
    write_song(song_dir, song_name: 'Test Song', include_zip: true)
    verified_zip = store.open_zip('test_song')

    assert_raises(IOError) do
      verified_zip.each { raise IOError, 'client disconnected' }
    end

    assert verified_zip.closed?
  end

  test 'open zip rejects a file replaced between validation and open' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'test_song')
    write_song(song_dir, song_name: 'Test Song', include_zip: true)
    zip_path = File.join(song_dir, 'sounds.zip')
    original_zip_path = File.join(song_dir, 'original-sounds.zip')
    outside_zip = File.join(@outside_root, 'replacement.zip')
    File.binwrite(outside_zip, 'replacement zip')
    original_open = File.method(:open)
    replaced = false
    replacing_open = proc do |path, *args, **kwargs, &block|
      if path == zip_path && !replaced
        File.rename(zip_path, original_zip_path)
        File.symlink(outside_zip, zip_path)
        replaced = true
      end
      original_open.call(path, *args, **kwargs, &block)
    end

    error = File.stub(:open, replacing_open) do
      assert_raises(RuntimeError) { store.open_zip('test_song') }
    end

    assert replaced
    assert_match(/Unsafe song storage path/, error.message)
    assert_equal 'replacement zip', File.binread(outside_zip)
  end

  test 'open zip keeps streaming the original descriptor after pathname replacement' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'test_song')
    write_song(song_dir, song_name: 'Test Song', include_zip: true)
    zip_path = File.join(song_dir, 'sounds.zip')
    original_zip_path = File.join(song_dir, 'original-sounds.zip')
    original_bytes = File.binread(zip_path)
    outside_zip = File.join(@outside_root, 'replacement.zip')
    File.binwrite(outside_zip, 'replacement zip')

    verified_zip = store.open_zip('test_song')
    File.rename(zip_path, original_zip_path)
    File.symlink(outside_zip, zip_path)

    assert_equal original_bytes, verified_zip.each.to_a.join
    assert verified_zip.closed?
    assert_equal 'replacement zip', File.binread(zip_path)
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

    outside_zip = File.join(@outside_root, 'external-list.zip')
    File.write(outside_zip, 'external list zip', mode: 'w', encoding: 'UTF-8')
    zip_link_song = File.join(store.songs_root, 'zip_link_song')
    write_song(zip_link_song, song_name: 'ZIP Link Song', include_zip: false)
    File.symlink(outside_zip, File.join(zip_link_song, 'sounds.zip'))

    songs = store.list

    assert File.symlink?(song_link)
    assert File.symlink?(File.join(manifest_link_song, 'song.json'))
    assert File.symlink?(File.join(zip_link_song, 'sounds.zip'))
    assert_empty songs
    assert_equal({ 'song_name' => 'External Manifest' }, JSON.parse(File.read(outside_manifest, encoding: 'UTF-8')))
    assert File.file?(File.join(outside_song, 'sounds.zip'))
    assert_equal 'external list zip', File.read(outside_zip, encoding: 'UTF-8')
  end

  test 'list rejects a manifest replaced between pathname validation and open' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'replace_manifest')
    write_song(song_dir, song_name: 'Original Song', include_zip: true)
    manifest_path = File.join(song_dir, 'song.json')
    outside_manifest = File.join(@outside_root, 'replacement-manifest.json')
    File.write(outside_manifest, JSON.generate('song_name' => 'Outside Song'), mode: 'w', encoding: 'UTF-8')
    original_open = File.method(:open)
    replaced = false
    replacing_open = proc do |path, *args, **kwargs, &block|
      if path == manifest_path && !replaced
        File.unlink(manifest_path)
        File.symlink(outside_manifest, manifest_path)
        replaced = true
      end
      original_open.call(path, *args, **kwargs, &block)
    end

    songs = File.stub(:open, replacing_open) { store.list }

    assert replaced
    assert_empty songs
    assert_equal 'Outside Song', JSON.parse(File.read(outside_manifest, encoding: 'UTF-8'))['song_name']
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

  test 'open zip preserves missing symlink dangling symlink and non-regular rejection' do
    store = UserSongStore.new(@repo_root)

    assert_raises(RuntimeError) { store.open_zip('missing_song') }

    song_dir = File.join(store.songs_root, 'test_song')
    FileUtils.mkdir_p(song_dir)
    assert_raises(RuntimeError) { store.open_zip('test_song') }

    zip_path = File.join(song_dir, 'sounds.zip')
    FileUtils.mkdir_p(zip_path)
    assert_raises(RuntimeError) { store.open_zip('test_song') }
    Dir.rmdir(zip_path)

    outside_zip = File.join(@outside_root, 'outside.zip')
    File.binwrite(outside_zip, 'outside zip')
    File.symlink(outside_zip, zip_path)
    assert_raises(RuntimeError) { store.open_zip('test_song') }
    File.unlink(zip_path)

    File.symlink(File.join(@outside_root, 'missing.zip'), zip_path)
    assert_raises(RuntimeError) { store.open_zip('test_song') }
  end

  test 'zip path rejects an unsafe filename through the shared filename validator' do
    store = UserSongStore.new(@repo_root)

    error = assert_raises(RuntimeError) { store.zip_path('../evil') }

    assert_match(/Invalid song filename/, error.message)
  end

  test 'open zip rejects an unsafe filename through the shared filename validator' do
    store = UserSongStore.new(@repo_root)

    error = assert_raises(RuntimeError) { store.open_zip('../evil') }

    assert_match(/Invalid song filename/, error.message)
  end

  test 'remove unlinks a dangling terminal song symlink' do
    store = UserSongStore.new(@repo_root)
    missing_target = File.join(@outside_root, 'missing_target')
    song_link = File.join(store.songs_root, 'dangling_song')
    File.symlink(missing_target, song_link)

    assert_equal true, store.remove!('dangling_song')
    refute File.symlink?(song_link)
    refute File.exist?(missing_target)
  end

  test 'remove does not follow a nested symlink outside the song directory' do
    store = UserSongStore.new(@repo_root)
    outside_directory = File.join(@outside_root, 'nested_target')
    marker_path = write_marker(outside_directory)
    song_dir = File.join(store.songs_root, 'nested_song')
    FileUtils.mkdir_p(song_dir)
    File.write(File.join(song_dir, 'local.txt'), 'local', mode: 'w', encoding: 'UTF-8')
    File.symlink(outside_directory, File.join(song_dir, 'outside_link'))

    assert_equal true, store.remove!('nested_song')

    refute File.exist?(song_dir)
    assert_equal 'outside marker', File.read(marker_path, encoding: 'UTF-8')
  end

  test 'remove uses secure recursive deletion for a normal directory' do
    store = UserSongStore.new(@repo_root)
    song_dir = File.join(store.songs_root, 'secure_remove')
    FileUtils.mkdir_p(song_dir)
    File.write(File.join(song_dir, 'local.txt'), 'local', mode: 'w', encoding: 'UTF-8')
    original_remove = FileUtils.method(:remove_entry_secure)
    called = false
    secure_remove = proc do |path, force = false|
      called = true
      original_remove.call(path, force)
    end

    FileUtils.stub(:remove_entry_secure, secure_remove) do
      assert_equal true, store.remove!('secure_remove')
    end

    assert called
    refute File.exist?(song_dir)
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
