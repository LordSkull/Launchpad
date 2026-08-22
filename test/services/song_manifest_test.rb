require 'test_helper'
require 'tmpdir'
require 'json'
require Rails.root.join('script', 'song_tool').to_s

class SongManifestTest < ActiveSupport::TestCase
  test 'audio sample filename resolution preserves legacy mp3 fallback and explicit formats' do
    assert_equal 'kick.mp3', AudioSample.resolve_filename('kick')
    assert_equal 'kick.wav', AudioSample.resolve_filename('kick.wav')
    assert_equal 'vocal.mp3', AudioSample.resolve_filename('vocal.mp3')
    assert_equal 'synth.ogg', AudioSample.resolve_filename('synth.ogg')
    assert_equal 'SAMPLE.WAV', AudioSample.resolve_filename('SAMPLE.WAV')
    assert_equal 'voice.MP3', AudioSample.resolve_filename('voice.MP3')
    assert_equal 'SYNTH.OGG', AudioSample.resolve_filename('SYNTH.OGG')
    assert AudioSample.supported?('kick.ogg')
    refute AudioSample.supported?('notes.txt')
    refute AudioSample.supported?('kick.flac')
    assert_equal 'kick.flac.mp3', AudioSample.resolve_filename('kick.flac')
  end

  test 'valid minimal manifest is accepted' do
    Dir.mktmpdir do |root|
      manifest = build_manifest(root, valid_manifest_hash)

      assert manifest.valid?
      assert_empty manifest.errors
    end
  end

  test 'legacy manifest without chain_count uses four chains' do
    Dir.mktmpdir do |root|
      data = valid_manifest_hash
      refute data.key?('chain_count')

      manifest = build_manifest(root, data)

      assert manifest.valid?, manifest.errors.inspect
      assert_equal 4, manifest.effective_chain_count
    end
  end

  test 'explicit chain counts from four through eight are accepted' do
    Dir.mktmpdir do |root|
      (4..8).each do |chain_count|
        manifest = build_manifest(root, manifest_hash_for_chain_count(chain_count))

        assert manifest.valid?, "Expected chain_count #{chain_count} to be valid: #{manifest.errors.inspect}"
        assert_equal chain_count, manifest.effective_chain_count
      end
    end
  end

  test 'chain_count must be an integer from four through eight when present' do
    Dir.mktmpdir do |root|
      [3, 9, 0, -1, '5', 5.0, nil].each do |chain_count|
        manifest = build_manifest(root, valid_manifest_hash.merge('chain_count' => chain_count))

        refute manifest.valid?, "Expected chain_count #{chain_count.inspect} to be invalid"
        assert manifest.errors.any? { |error| error.include?('chain_count') },
               "Expected a chain_count error for #{chain_count.inspect}: #{manifest.errors.inspect}"
      end
    end
  end

  test 'declared chains must be contiguous' do
    Dir.mktmpdir do |root|
      data = manifest_hash_for_chain_count(6)
      %w[mappings holdToPlay linkedAreas].each { |section| data[section].delete('chain5') }

      manifest = build_manifest(root, data)

      refute manifest.valid?
      assert manifest.errors.any? { |error| error.include?('mappings.chain5') }
      assert manifest.errors.any? { |error| error.include?('holdToPlay.chain5') }
      assert manifest.errors.any? { |error| error.include?('linkedAreas.chain5') }
    end
  end

  test 'each declared chain is required in every chain section' do
    %w[mappings holdToPlay linkedAreas].each do |section|
      Dir.mktmpdir do |root|
        data = manifest_hash_for_chain_count(5)
        data[section].delete('chain5')

        manifest = build_manifest(root, data)

        refute manifest.valid?, "Expected missing #{section}.chain5 to be invalid"
        assert manifest.errors.any? { |error| error.include?("#{section}.chain5") }, manifest.errors.inspect
      end
    end
  end

  test 'chain keys beyond the declared count are rejected in every chain section' do
    %w[mappings holdToPlay linkedAreas].each do |section|
      Dir.mktmpdir do |root|
        data = manifest_hash_for_chain_count(5)
        data[section]['chain6'] = section == 'mappings' ? Array.new(48) { '' } : []

        manifest = build_manifest(root, data)

        refute manifest.valid?, "Expected extra #{section}.chain6 to be invalid"
        assert manifest.errors.any? { |error| error.include?("#{section}.chain6") }, manifest.errors.inspect
      end
    end
  end

  test 'chain0 and chain9 are rejected' do
    %w[chain0 chain9].each do |chain|
      Dir.mktmpdir do |root|
        data = manifest_hash_for_chain_count(8)
        data['mappings'][chain] = Array.new(48) { '' }

        manifest = build_manifest(root, data)

        refute manifest.valid?
        assert manifest.errors.any? { |error| error.include?("mappings.#{chain}") }, manifest.errors.inspect
      end
    end
  end

  test 'chain8 validates mappings zip references hold to play linked areas and mixed audio' do
    Dir.mktmpdir do |root|
      data = manifest_hash_for_chain_count(8)
      data['mappings']['chain8'][0] = 'kick.wav'
      data['mappings']['chain8'][1] = 'vocal.mp3'
      data['mappings']['chain8'][2] = 'synth.ogg'
      data['holdToPlay']['chain8'] = [0]
      data['linkedAreas']['chain8'] = [[0, 1, 2]]

      manifest = build_manifest(
        root,
        data,
        entries: ['sounds/chain8/kick.wav', 'sounds/chain8/vocal.mp3', 'sounds/chain8/synth.ogg']
      )

      assert manifest.valid?, manifest.errors.inspect
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

  test 'ogg mapping is accepted' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('synth.ogg')
      manifest = build_manifest(root, data, entries: ['sounds/chain1/synth.ogg'])

      assert manifest.valid?, manifest.errors.inspect
    end
  end

  test 'mixed mp3 wav and ogg mappings are accepted' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('kick.wav', 'vocal.mp3', 'synth.ogg')
      manifest = build_manifest(
        root,
        data,
        entries: ['sounds/chain1/kick.wav', 'sounds/chain1/vocal.mp3', 'sounds/chain1/synth.ogg']
      )

      assert manifest.valid?, manifest.errors.inspect
    end
  end

  test 'supported audio extensions are recognized case insensitively' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('SAMPLE.WAV', 'voice.MP3', 'SYNTH.OGG')
      manifest = build_manifest(
        root,
        data,
        entries: ['sounds/chain1/SAMPLE.WAV', 'sounds/chain1/voice.MP3', 'sounds/chain1/SYNTH.OGG']
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

  test 'missing ogg entry is rejected and a real flac entry remains unsupported' do
    Dir.mktmpdir do |root|
      data = manifest_with_samples('missing.ogg', 'kick.flac')
      manifest = build_manifest(
        root,
        data,
        entries: ['sounds/chain1/other.ogg', 'sounds/chain1/kick.flac']
      )

      refute manifest.valid?
      assert manifest.errors.any? { |error| error.include?('missing.ogg') }
      assert manifest.errors.any? { |error| error.include?('kick.flac.mp3') }
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

  def manifest_hash_for_chain_count(chain_count)
    chains = (1..chain_count).map { |number| "chain#{number}" }

    {
      'chain_count' => chain_count,
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
