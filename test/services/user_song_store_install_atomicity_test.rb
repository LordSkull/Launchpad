require 'test_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require 'minitest/mock'
require Rails.root.join('script', 'song_tool').to_s

class UserSongStoreInstallAtomicityTest < ActiveSupport::TestCase
  def setup
    @temporary_root = Dir.mktmpdir('launchpad-song-store-atomicity-')
    @store = UserSongStore.new(@temporary_root)
    @manifest = build_valid_manifest
    @sibling_path = File.join(@store.songs_root, 'sibling.txt')
    File.write(@sibling_path, 'keep sibling', mode: 'w', encoding: 'UTF-8')
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if @temporary_root && File.exist?(@temporary_root)
  end

  test 'normal install publishes both files and leaves no temp directory' do
    result = @store.install!(@manifest)

    destination = destination_path
    assert File.directory?(destination)
    assert_equal %w[song.json sounds.zip], Dir.children(destination).sort
    assert File.file?(lock_path)
    assert_equal ['test_song'], @store.list.map { |song| song['filename'] }
    assert_equal 'test_song', result['filename']
    assert_equal File.join('user_data', 'songs', 'test_song', 'song.json'), result['manifest_path']
    assert_equal File.join('user_data', 'songs', 'test_song', 'sounds.zip'), result['zip_path']
    assert_empty temp_directories
    assert_install_lock_available
    assert_sibling_unchanged
  end

  test 'destination collision fails before temp creation and preserves existing content' do
    destination = destination_path
    FileUtils.mkdir_p(destination)
    marker_path = File.join(destination, 'existing.txt')
    File.write(marker_path, 'existing destination', mode: 'w', encoding: 'UTF-8')

    error = assert_raises(RuntimeError) { @store.install!(@manifest) }

    assert_match(/already installed/, error.message)
    assert_equal 'existing destination', File.read(marker_path, encoding: 'UTF-8')
    assert_equal ['existing.txt'], Dir.children(destination)
    assert_empty temp_directories
    assert_install_lock_available
    assert_sibling_unchanged
  end

  test 'manifest write failure propagates and removes the temp directory' do
    write_failure = proc { |_path, *_args, **_kwargs| raise IOError, 'simulated manifest write failure' }

    error = assert_raises(IOError) do
      File.stub(:write, write_failure) { @store.install!(@manifest) }
    end

    assert_equal 'simulated manifest write failure', error.message
    refute File.exist?(destination_path)
    assert_empty temp_directories
    assert_install_lock_available
    assert_sibling_unchanged
  end

  test 'zip copy failure occurs after manifest write and removes the temp directory' do
    manifest_was_written = false
    copy_failure = proc do |_source, destination, *_args, **_kwargs|
      manifest_was_written = File.file?(File.join(File.dirname(destination), 'song.json'))
      raise IOError, 'simulated zip copy failure'
    end

    error = assert_raises(IOError) do
      FileUtils.stub(:cp, copy_failure) { @store.install!(@manifest) }
    end

    assert_equal 'simulated zip copy failure', error.message
    assert manifest_was_written
    refute File.exist?(destination_path)
    assert_empty temp_directories
    assert_install_lock_available
    assert_sibling_unchanged
  end

  test 'final move failure sees a complete temp directory and cleanup removes it' do
    observed = {}
    move_failure = proc do |source, destination, *_args, **_kwargs|
      observed[:source_name] = File.basename(source)
      observed[:destination] = destination
      observed[:children] = Dir.children(source).sort
      observed[:same_device] = File.stat(source).dev == File.stat(File.dirname(destination)).dev
      raise IOError, 'simulated final move failure'
    end

    error = assert_raises(IOError) do
      FileUtils.stub(:mv, move_failure) { @store.install!(@manifest) }
    end

    assert_equal 'simulated final move failure', error.message
    assert_match(temp_name_pattern, observed[:source_name])
    assert_equal destination_path, observed[:destination]
    assert_equal %w[song.json sounds.zip], observed[:children]
    assert_equal true, observed[:same_device]
    refute File.exist?(destination_path)
    assert_empty temp_directories
    assert_install_lock_available
    assert_sibling_unchanged
  end

  test 'a destination created before publication causes an error and is preserved' do
    original_copy = FileUtils.method(:cp)
    move_called = false
    concurrent_marker = File.join(destination_path, 'concurrent.txt')
    racing_copy = proc do |source, destination, *args, **kwargs|
      original_copy.call(source, destination, *args, **kwargs)
      FileUtils.mkdir_p(destination_path)
      File.write(concurrent_marker, 'concurrent destination', mode: 'w', encoding: 'UTF-8')
    end
    move_probe = proc { |_source, _destination, *_args, **_kwargs| move_called = true }

    result = nil
    error = assert_raises(RuntimeError) do
      FileUtils.stub(:cp, racing_copy) do
        FileUtils.stub(:mv, move_probe) { result = @store.install!(@manifest) }
      end
    end

    assert_match(/already installed/, error.message)
    assert_nil result
    refute move_called
    assert_equal 'concurrent destination', File.read(concurrent_marker, encoding: 'UTF-8')
    assert_equal ['concurrent.txt'], Dir.children(destination_path)
    refute File.exist?(File.join(destination_path, 'song.json'))
    refute File.exist?(File.join(destination_path, 'sounds.zip'))
    assert_empty @store.list
    assert_empty temp_directories
    assert_install_lock_available
    assert_sibling_unchanged
  end

  test 'a symlink at the install lock path is rejected without touching its target' do
    outside_lock = File.join(@temporary_root, 'outside-install.lock')
    File.write(outside_lock, 'outside lock marker', mode: 'w', encoding: 'UTF-8')
    File.symlink(outside_lock, lock_path)

    error = assert_raises(RuntimeError) { @store.install!(@manifest) }

    assert_match(/Unsafe song storage path/, error.message)
    assert File.symlink?(lock_path)
    assert_equal 'outside lock marker', File.read(outside_lock, encoding: 'UTF-8')
    refute File.exist?(destination_path)
    assert_empty temp_directories
    assert_sibling_unchanged
  end

  test 'list hides incomplete and complete orphan temp directories' do
    empty_temp = create_orphan_temp('.test_song.tmp-123-1', manifest: false, zip: false)
    manifest_temp = create_orphan_temp('.test_song.tmp-123-2', manifest: true, zip: false)
    complete_temp = create_orphan_temp('.test_song.tmp-123-3', manifest: true, zip: true)

    songs = @store.list

    [empty_temp, manifest_temp, complete_temp].each do |path|
      assert_match(temp_name_pattern, File.basename(path))
      assert File.directory?(path)
    end
    assert_empty songs
    assert_sibling_unchanged
  end

  test 'two cooperative installers are serialized and receive consecutive song numbers' do
    first_manifest = build_valid_manifest('first_song')
    second_manifest = build_valid_manifest('second_song')
    first_store = UserSongStore.new(@temporary_root)
    second_store = UserSongStore.new(@temporary_root)
    original_copy = FileUtils.method(:cp)
    first_copy_started = Queue.new
    release_first_copy = Queue.new
    second_install_started = Queue.new
    copy_with_barrier = proc do |source, destination, *args, **kwargs|
      if source == first_manifest.zip_path
        first_copy_started << true
        release_first_copy.pop
      end
      original_copy.call(source, destination, *args, **kwargs)
    end
    first_result = nil
    second_result = nil
    lock_was_held = nil

    FileUtils.stub(:cp, copy_with_barrier) do
      first_thread = Thread.new { first_store.install!(first_manifest) }
      first_copy_started.pop

      File.open(lock_path, File::RDWR) do |lock|
        lock_was_held = lock.flock(File::LOCK_EX | File::LOCK_NB) == false
      end

      second_thread = Thread.new do
        second_install_started << true
        second_store.install!(second_manifest)
      end
      second_install_started.pop
      release_first_copy << true

      first_result = first_thread.value
      second_result = second_thread.value
    end

    assert lock_was_held
    assert_equal first_result['song_number'] + 1, second_result['song_number']
    assert_equal 2, [first_result['song_number'], second_result['song_number']].uniq.length
    assert_equal %w[first_song second_song], @store.list.map { |song| song['filename'] }.sort
    [first_result, second_result].each do |result|
      installed_path = File.join(@store.songs_root, result['filename'])
      assert_equal %w[song.json sounds.zip], Dir.children(installed_path).sort
    end
    assert_empty temp_directories
    assert_sibling_unchanged
  end

  private

  def destination_path
    File.join(@store.songs_root, 'test_song')
  end

  def lock_path
    File.join(@store.songs_root, '.install.lock')
  end

  def temp_name_pattern
    /\A\.(?:test_song|first_song|second_song)\.tmp-\d+-\d+\z/
  end

  def temp_directories
    Dir.children(@store.songs_root).select do |entry|
      entry.match?(temp_name_pattern) && File.directory?(File.join(@store.songs_root, entry))
    end.sort
  end

  def create_orphan_temp(name, manifest:, zip:)
    path = File.join(@store.songs_root, name)
    FileUtils.mkdir_p(path)
    data = { 'song_name' => "Orphan #{name}", 'filename' => 'untrusted' }
    File.write(File.join(path, 'song.json'), JSON.generate(data), mode: 'w', encoding: 'UTF-8') if manifest
    File.write(File.join(path, 'sounds.zip'), 'zip marker', mode: 'w', encoding: 'UTF-8') if zip
    path
  end

  def build_valid_manifest(filename = 'test_song')
    input_dir = File.join(@temporary_root, 'inputs', filename)
    FileUtils.mkdir_p(input_dir)
    manifest_path = File.join(input_dir, 'song.json')
    zip_path = File.join(input_dir, 'sounds.zip')
    File.write(manifest_path, JSON.generate(valid_manifest_hash(filename)), mode: 'w', encoding: 'UTF-8')
    write_empty_zip(zip_path)

    manifest = SongManifest.new(manifest_path, zip_path).validate!
    raise "Invalid atomicity test manifest: #{manifest.errors.inspect}" unless manifest.valid?
    manifest
  end

  def valid_manifest_hash(filename)
    chains = %w[chain1 chain2 chain3 chain4]
    {
      'song_name' => "Atomicity Test Song #{filename}",
      'filename' => filename,
      'bpm' => 120,
      'mappings' => chains.to_h { |chain| [chain, Array.new(48) { '' }] },
      'holdToPlay' => chains.to_h { |chain| [chain, []] },
      'linkedAreas' => chains.to_h { |chain| [chain, []] }
    }
  end

  def write_empty_zip(path)
    eocd = [0x06054b50, 0, 0, 0, 0, 0, 0, 0].pack('VvvvvVVv')
    File.binwrite(path, eocd)
  end

  def assert_sibling_unchanged
    assert_equal 'keep sibling', File.read(@sibling_path, encoding: 'UTF-8')
  end

  def assert_install_lock_available
    File.open(lock_path, File::RDWR) do |lock|
      assert_equal 0, lock.flock(File::LOCK_EX | File::LOCK_NB)
      assert_equal 0, lock.flock(File::LOCK_UN)
    end
  end
end
