require 'test_helper'
require 'tmpdir'
require 'json'
require 'fileutils'
require Rails.root.join('script', 'song_tool').to_s

class UserSongStoreTest < ActiveSupport::TestCase
  test 'install writes song files only under the store root' do
    Dir.mktmpdir do |root|
      marker_path = write_external_marker(root)
      manifest = build_valid_manifest(root)
      store = UserSongStore.new(root)

      result = store.install!(manifest)

      song_dir = File.join(store.songs_root, 'test_song')
      installed_manifest_path = File.join(song_dir, 'song.json')
      installed_zip_path = File.join(song_dir, 'sounds.zip')

      assert File.file?(installed_manifest_path)
      assert File.file?(installed_zip_path)
      assert_equal File.binread(manifest.zip_path), File.binread(installed_zip_path)
      assert_equal %w[song.json sounds.zip], Dir.children(song_dir).sort

      installed_data = JSON.parse(File.read(installed_manifest_path, encoding: 'UTF-8'))
      assert_equal 'Test Song', installed_data['song_name']
      assert_equal 'test_song', installed_data['filename']
      assert_equal 120, installed_data['bpm']
      assert_equal 1, installed_data['song_number']
      assert_equal 1, installed_data['schema_version']
      assert_equal true, installed_data['user_installed']

      assert_equal File.join('user_data', 'songs', 'test_song', 'song.json'), result['manifest_path']
      assert_equal File.join('user_data', 'songs', 'test_song', 'sounds.zip'), result['zip_path']
      assert_equal 'outside marker', File.read(marker_path, encoding: 'UTF-8')
    end
  end

  test 'remove deletes an installed user song' do
    Dir.mktmpdir do |root|
      marker_path = write_external_marker(root)
      manifest = build_valid_manifest(root)
      store = UserSongStore.new(root)
      store.install!(manifest)
      song_dir = File.join(store.songs_root, 'test_song')

      assert File.directory?(song_dir)
      assert_equal true, store.remove!('test_song')

      refute File.exist?(song_dir)
      assert File.directory?(store.songs_root)
      assert_equal 'outside marker', File.read(marker_path, encoding: 'UTF-8')
    end
  end

  test 'remove rejects unsafe filenames without touching external files' do
    Dir.mktmpdir do |root|
      marker_path = write_external_marker(root)
      manifest = build_valid_manifest(root)
      store = UserSongStore.new(root)
      store.install!(manifest)
      song_dir = File.join(store.songs_root, 'test_song')

      [
        '', ' name', 'name ', '../outside', '../../outside', '/outside',
        'C:\\outside', 'C:/outside', '\\\\server\\share', 'foo/bar',
        'foo\\bar', '.', '..', '...', '%2e%2e', 'é', '.hidden'
      ].each do |filename|
        assert_raises(RuntimeError, "Expected #{filename.inspect} to be rejected") do
          store.remove!(filename)
        end

        assert File.directory?(song_dir), "Expected the installed song to survive #{filename.inspect}"
        assert_equal 'outside marker', File.read(marker_path, encoding: 'UTF-8')
      end
    end
  end

  test 'catalog ignores malformed component names' do
    Dir.mktmpdir do |root|
      store = UserSongStore.new(root)
      write_store_entry(store, 'normal_song', JSON.generate('song_name' => 'Normal Song'))
      write_store_entry(store, ' malformed', JSON.generate('song_name' => 'Malformed Song'))

      assert_equal ['normal_song'], store.list.map { |song| song['filename'] }
    end
  end

  test 'leading whitespace identifier cannot alias and remove a valid sibling' do
    Dir.mktmpdir do |root|
      store = UserSongStore.new(root)
      victim_dir = File.join(store.songs_root, 'victim')
      write_store_entry(store, 'victim', JSON.generate('song_name' => 'Victim'))
      write_store_entry(store, ' victim', JSON.generate('song_name' => 'Malformed Alias'))

      assert_raises(RuntimeError) { store.remove!(' victim') }
      assert File.directory?(victim_dir)
      assert_equal 'Victim', JSON.parse(File.read(File.join(victim_dir, 'song.json')))['song_name']
    end
  end

  test 'list preserves valid manifest fields and derives client fields from the directory' do
    Dir.mktmpdir do |root|
      store = UserSongStore.new(root)
      manifest = {
        'song_name' => 'Listed Song',
        'filename' => '../untrusted_manifest_value',
        'bpm' => '120.5',
        'song_number' => '007',
        'schema_version' => 'legacy',
        'unknown_key' => { 'keep' => true },
        'user_installed' => false
      }
      write_store_entry(store, 'actual_directory', JSON.generate(manifest))

      songs = store.list

      expected = manifest.merge(
        'filename' => 'actual_directory',
        'user_installed' => true
      )
      assert_equal [expected], songs
    end
  end

  test 'list skips every supported non object top level JSON value' do
    Dir.mktmpdir do |root|
      store = UserSongStore.new(root)
      {
        'array_value' => '[]',
        'string_value' => '"hello"',
        'number_value' => '123',
        'boolean_value' => 'true',
        'null_value' => 'null'
      }.each do |entry, json|
        write_store_entry(store, entry, json)
      end
      write_store_entry(store, 'valid_object', JSON.generate('song_name' => 'Valid Object'))

      songs = store.list

      assert_equal ['valid_object'], songs.map { |song| song['filename'] }
      assert_equal ['Valid Object'], songs.map { |song| song['song_name'] }
    end
  end

  test 'list keeps valid entries around a corrupt entry in directory order' do
    Dir.mktmpdir do |root|
      store = UserSongStore.new(root)
      write_store_entry(store, 'a_valid', JSON.generate('song_name' => 'First'))
      write_store_entry(store, 'b_broken', '[]')
      write_store_entry(store, 'c_valid', JSON.generate('song_name' => 'Third'))

      songs = store.list

      assert_equal %w[a_valid c_valid], songs.map { |song| song['filename'] }
      assert_equal ['First', 'Third'], songs.map { |song| song['song_name'] }
    end
  end

  test 'list skips missing invalid and incomplete song entries' do
    Dir.mktmpdir do |root|
      store = UserSongStore.new(root)
      FileUtils.mkdir_p(File.join(store.songs_root, 'missing_manifest'))
      write_store_entry(store, 'invalid_manifest', '{invalid')
      write_store_entry(store, 'missing_zip', JSON.generate('song_name' => 'No ZIP'), include_zip: false)
      write_store_entry(store, 'complete_song', JSON.generate('song_name' => 'Complete'))

      songs = store.list

      assert_equal ['complete_song'], songs.map { |song| song['filename'] }
      assert_equal ['Complete'], songs.map { |song| song['song_name'] }
      refute File.exist?(File.join(store.songs_root, 'missing_zip', 'sounds.zip'))
    end
  end

  private

  def valid_manifest_hash
    chains = %w[chain1 chain2 chain3 chain4]

    {
      'song_name' => 'Test Song',
      'filename' => 'test_song',
      'bpm' => 120,
      'mappings' => chains.to_h { |chain| [chain, Array.new(48) { '' }] },
      'holdToPlay' => chains.to_h { |chain| [chain, []] },
      'linkedAreas' => chains.to_h { |chain| [chain, []] }
    }
  end

  def build_valid_manifest(root)
    input_dir = File.join(root, 'inputs')
    FileUtils.mkdir_p(input_dir)
    manifest_path = File.join(input_dir, 'song.json')
    zip_path = File.join(input_dir, 'sounds.zip')
    File.write(manifest_path, JSON.generate(valid_manifest_hash), mode: 'w', encoding: 'UTF-8')
    write_empty_zip(zip_path)

    manifest = SongManifest.new(manifest_path, zip_path).validate!
    assert manifest.valid?, "Expected test manifest to be valid, got: #{manifest.errors.inspect}"
    manifest
  end

  def write_empty_zip(path)
    eocd = [0x06054b50, 0, 0, 0, 0, 0, 0, 0].pack('VvvvvVVv')
    File.binwrite(path, eocd)
  end

  def write_external_marker(root)
    outside_dir = File.join(root, 'outside')
    FileUtils.mkdir_p(outside_dir)
    marker_path = File.join(outside_dir, 'marker.txt')
    File.write(marker_path, 'outside marker', mode: 'w', encoding: 'UTF-8')
    marker_path
  end

  def write_store_entry(store, entry, json, include_zip: true)
    song_dir = File.join(store.songs_root, entry)
    FileUtils.mkdir_p(song_dir)
    File.write(File.join(song_dir, 'song.json'), json, mode: 'w', encoding: 'UTF-8')
    File.write(File.join(song_dir, 'sounds.zip'), 'zip marker', mode: 'w', encoding: 'UTF-8') if include_zip
  end
end
