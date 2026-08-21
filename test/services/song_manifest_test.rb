require 'test_helper'
require 'tmpdir'
require 'json'
require Rails.root.join('script', 'song_tool').to_s

class SongManifestTest < ActiveSupport::TestCase
  test 'audio sample filename resolution preserves legacy mp3 fallback and explicit formats' do
    assert_equal 'kick.mp3', AudioSample.resolve_filename('kick')
    assert_equal 'kick.wav', AudioSample.resolve_filename('kick.wav')
    assert_equal 'vocal.mp3', AudioSample.resolve_filename('vocal.mp3')
    assert_equal 'SAMPLE.WAV', AudioSample.resolve_filename('SAMPLE.WAV')
    assert_equal 'voice.MP3', AudioSample.resolve_filename('voice.MP3')
    refute AudioSample.supported?('notes.txt')
  end

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

  test 'legacy mapping without extension still resolves to mp3' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('kick')
      manifest = build_manifest(root, data, entries: ['sounds/chain1/kick.mp3'])

      assert manifest.valid?, manifest.errors.inspect
      assert_empty manifest.errors
    end
  end

  test 'explicit mp3 mapping is accepted' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('vocal.mp3')
      manifest = build_manifest(root, data, entries: ['sounds/chain1/vocal.mp3'])

      assert manifest.valid?, manifest.errors.inspect
    end
  end

  test 'wav mapping is accepted' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('kick.wav')
      manifest = build_manifest(root, data, entries: ['sounds/chain1/kick.wav'])

      assert manifest.valid?, manifest.errors.inspect
    end
  end

  test 'mixed mp3 and wav mappings are accepted' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('kick.wav', 'vocal.mp3')
      manifest = build_manifest(
        root,
        data,
        entries: ['sounds/chain1/kick.wav', 'sounds/chain1/vocal.mp3']
      )

      assert manifest.valid?, manifest.errors.inspect
    end
  end

  test 'supported audio extensions are recognized case insensitively' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('SAMPLE.WAV', 'voice.MP3')
      manifest = build_manifest(
        root,
        data,
        entries: ['sounds/chain1/SAMPLE.WAV', 'sounds/chain1/voice.MP3']
      )

      assert manifest.valid?, manifest.errors.inspect
    end
  end

  test 'non audio zip entries do not satisfy a sample mapping' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('notes.txt')
      manifest = build_manifest(root, data, entries: ['sounds/chain1/notes.txt'])

      refute manifest.valid?
      assert manifest.errors.any? { |error| error.include?('notes.txt.mp3') }
    end
  end

  test 'missing wav entry is rejected' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('missing.wav')
      manifest = build_manifest(root, data, entries: ['sounds/chain1/other.wav'])

      refute manifest.valid?
      assert manifest.errors.any? { |error| error.include?('missing.wav') }
    end
  end

  test 'sample mappings cannot contain paths' do
    Dir.mktmpdir do |root|
      ['../evil.wav', '..\\evil.wav', '/absolute.wav'].each do |sample|
        data = manifest_with_samples(sample)
        manifest = build_manifest(root, data, entries: [])

        refute manifest.valid?, "Expected #{sample.inspect} to be invalid"
        assert manifest.errors.any? { |error| error.include?('sample filename only') || error.include?('sample basename only') },
               "Expected a sample path error for #{sample.inspect}, got: #{manifest.errors.inspect}"
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

  def manifest_with_samples(*samples)
    data = valid_manifest_hash
    samples.each_with_index { |sample, index| data['mappings']['chain1'][index] = sample }
    data
  end

  def build_manifest(root, data, entries: [])
    manifest_path = File.join(root, 'song.json')
    zip_path = File.join(root, 'sounds.zip')
    File.write(manifest_path, JSON.generate(data), mode: 'w', encoding: 'UTF-8')
    write_zip(zip_path, entries)

    SongManifest.new(manifest_path, zip_path).validate!
  end

  def write_zip(path, entries)
    central_directory = entries.map { |entry| central_directory_entry(entry) }.join.b
    eocd = [
      0x06054b50, 0, 0, entries.length, entries.length,
      central_directory.bytesize, 0, 0
    ].pack('VvvvvVVv')
    File.binwrite(path, central_directory + eocd)
  end

  def central_directory_entry(name)
    name = name.b
    [
      0x02014b50, 20, 20, 0x0800, 0, 0, 0, 0, 0, 0,
      name.bytesize, 0, 0, 0, 0, 0, 0, 0
    ].pack('VvvvvvvVVVvvvvvVV') + name
  end
end
