require 'test_helper'
require 'tmpdir'
require 'json'
require Rails.root.join('script', 'song_tool').to_s

class SongManifestTest < ActiveSupport::TestCase
  test 'valid minimal manifest is accepted' do
    Dir.mktmpdir do |root|
      manifest = build_manifest(root, valid_manifest_hash)

      assert manifest.valid?
      assert_empty manifest.errors
    end
  end

  test 'mappings must contain exactly 48 entries' do
    Dir.mktmpdir do |root|
      [47, 49].each do |entry_count|
        data = valid_manifest_hash
        data['mappings']['chain1'] = Array.new(entry_count) { '' }

        manifest = build_manifest(root, data)

        refute manifest.valid?, "Expected a chain with #{entry_count} entries to be invalid"
        assert manifest.errors.any? { |error| error.include?('mappings.chain1') && error.include?('48') },
               "Expected a chain1 length error for #{entry_count} entries, got: #{manifest.errors.inspect}"
      end
    end
  end

  test 'manifest rejects unsafe filenames' do
    Dir.mktmpdir do |root|
      ['../evil', '../../evil', 'foo/bar', 'foo\\bar'].each do |filename|
        data = valid_manifest_hash
        data['filename'] = filename

        manifest = build_manifest(root, data)

        refute manifest.valid?, "Expected #{filename.inspect} to be invalid"
        assert manifest.errors.any? { |error| error.include?('filename') },
               "Expected a filename error for #{filename.inspect}, got: #{manifest.errors.inspect}"
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

  def build_manifest(root, data)
    manifest_path = File.join(root, 'song.json')
    zip_path = File.join(root, 'sounds.zip')
    File.write(manifest_path, JSON.generate(data), mode: 'w', encoding: 'UTF-8')
    write_empty_zip(zip_path)

    SongManifest.new(manifest_path, zip_path).validate!
  end

  def write_empty_zip(path)
    eocd = [0x06054b50, 0, 0, 0, 0, 0, 0, 0].pack('VvvvvVVv')
    File.binwrite(path, eocd)
  end
end
