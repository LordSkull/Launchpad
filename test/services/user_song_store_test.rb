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

      ['../evil', '../../evil', 'foo/bar', 'foo\\bar'].each do |filename|
        assert_raises(RuntimeError, "Expected #{filename.inspect} to be rejected") do
          store.remove!(filename)
        end

        assert File.directory?(song_dir), "Expected the installed song to survive #{filename.inspect}"
        assert_equal 'outside marker', File.read(marker_path, encoding: 'UTF-8')
      end
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
end
