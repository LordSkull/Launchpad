# frozen_string_literal: true

require 'json'
require 'fileutils'

class UserSongStore
  attr_reader :repo_root, :songs_root

  def initialize(repo_root)
    @repo_root = File.expand_path(repo_root)
    @songs_root = File.join(@repo_root, 'user_data', 'songs')
    FileUtils.mkdir_p(@songs_root)
  end

  def list
    return [] unless Dir.exist?(songs_root)

    Dir.entries(songs_root).sort.each_with_object([]) do |entry, songs|
      next if entry == '.' || entry == '..' || entry.start_with?('.')
      manifest_path = File.join(songs_root, entry, 'song.json')
      next unless File.file?(manifest_path)

      begin
        data = JSON.parse(File.read(manifest_path, encoding: 'UTF-8'))
        data['filename'] = entry
        data['user_installed'] = true
        songs << data
      rescue JSON::ParserError, Encoding::InvalidByteSequenceError => e
        warn "Skipping invalid user song #{entry}: #{e.message}"
      end
    end
  end

  def install!(manifest, allow_public_zip_conflict = false)
    raise 'Song package must be valid before installation.' unless manifest.valid?

    filename = normalize_filename(manifest.filename)
    target_dir = File.join(songs_root, filename)
    raise "Song '#{filename}' is already installed." if File.exist?(target_dir)

    public_zip = File.join(repo_root, 'public', 'zip', 'sounds', "#{filename}.zip")
    if File.exist?(public_zip) && !allow_public_zip_conflict
      raise "Filename '#{filename}' conflicts with a built-in song. Choose another ZIP filename."
    end

    number = manifest.song_number || next_song_number
    if existing_song_numbers.include?(number)
      raise "song_number #{number} already exists. Leave Song ID blank to auto-assign, or choose another ID."
    end

    data = deep_copy(manifest.data)
    data.delete('variable_name')
    data['schema_version'] = (data['schema_version'] || 1).to_i
    data['song_number'] = number
    data['filename'] = filename
    data['user_installed'] = true

    tmp_dir = target_dir + ".tmp-#{Process.pid}-#{rand(1_000_000)}"
    FileUtils.mkdir_p(tmp_dir)

    begin
      File.write(File.join(tmp_dir, 'song.json'), JSON.pretty_generate(data) + "\n", mode: 'w', encoding: 'UTF-8')
      FileUtils.cp(manifest.zip_path, File.join(tmp_dir, 'sounds.zip'))
      FileUtils.mv(tmp_dir, target_dir)
    rescue StandardError
      FileUtils.rm_rf(tmp_dir)
      raise
    end

    {
      'song_number' => number,
      'filename' => filename,
      'manifest_path' => relative(File.join(target_dir, 'song.json')),
      'zip_path' => relative(File.join(target_dir, 'sounds.zip'))
    }
  end

  def remove!(filename)
    filename = normalize_filename(filename)
    target_dir = File.join(songs_root, filename)
    raise "User song '#{filename}' is not installed." unless File.directory?(target_dir)

    FileUtils.rm_rf(target_dir)
    true
  end

  def zip_path(filename)
    filename = normalize_filename(filename)
    path = File.join(songs_root, filename, 'sounds.zip')
    raise "User song '#{filename}' was not found." unless File.file?(path)
    path
  end

  def installed?(filename)
    File.directory?(File.join(songs_root, normalize_filename(filename)))
  end

  def existing_song_numbers
    (built_in_song_numbers + user_song_numbers).uniq
  end

  def next_song_number
    (existing_song_numbers.max || 0) + 1
  end

  private

  def normalize_filename(value)
    filename = value.to_s.strip
    unless filename.match?(/\A[A-Za-z0-9_-]+\z/)
      raise "Invalid song filename '#{filename}'."
    end
    filename
  end

  def built_in_song_numbers
    pattern = File.join(repo_root, 'app', 'assets', 'javascripts', '*.js')
    Dir.glob(pattern).reject { |path| File.basename(path).start_with?('data_') }.map do |path|
      begin
        text = File.read(path, encoding: 'UTF-8')
        text.scan(/[\"']?song_number[\"']?\s*:\s*(\d+)/).flatten.map(&:to_i)
      rescue Encoding::InvalidByteSequenceError
        []
      end
    end.flatten.uniq
  end

  def user_song_numbers
    list.map { |song| song['song_number'].to_i }.select { |n| n.positive? }
  end

  def deep_copy(obj)
    JSON.parse(JSON.generate(obj))
  end

  def relative(path)
    path.sub(repo_root + File::SEPARATOR, '')
  end
end
