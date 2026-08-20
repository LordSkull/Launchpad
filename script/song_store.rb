# frozen_string_literal: true

require 'json'
require 'fileutils'

class UserSongStore
  attr_reader :repo_root, :songs_root

  def initialize(repo_root)
    @repo_root = File.expand_path(repo_root)
    @songs_root = File.join(@repo_root, 'user_data', 'songs')
    FileUtils.mkdir_p(@songs_root)
    ensure_safe_root!
  end

  def list
    real_root = ensure_safe_root!

    Dir.entries(songs_root).sort.each_with_object([]) do |entry, songs|
      next if entry == '.' || entry == '..' || entry.start_with?('.')
      song_dir = File.join(songs_root, entry)
      next unless safe_real_path?(song_dir, real_root, :directory)

      manifest_path = File.join(song_dir, 'song.json')
      next unless safe_real_path?(manifest_path, real_root, :file)

      zip_path = File.join(song_dir, 'sounds.zip')
      next unless safe_real_path?(zip_path, real_root, :file)

      begin
        data = JSON.parse(File.read(manifest_path, encoding: 'UTF-8'))
        next unless data.is_a?(Hash)

        data['filename'] = entry
        data['user_installed'] = true
        songs << data
      rescue JSON::ParserError, Encoding::InvalidByteSequenceError,
             Encoding::UndefinedConversionError, SystemCallError => e
        warn "Skipping invalid user song #{entry}: #{e.message}"
      end
    end
  end

  def install!(manifest, allow_public_zip_conflict = false)
    raise 'Song package must be valid before installation.' unless manifest.valid?

    with_install_lock do
      install_under_lock!(manifest, allow_public_zip_conflict)
    end
  end

  def remove!(filename)
    real_root = ensure_safe_root!
    filename = normalize_filename(filename)
    target_dir = File.join(songs_root, filename)
    target_stat = lstat(target_dir)
    raise "User song '#{filename}' is not installed." unless target_stat

    if target_stat.symlink?
      File.unlink(target_dir)
      return true
    end

    unless target_stat.directory? && safe_real_path?(target_dir, real_root, :directory)
      raise "User song '#{filename}' is not installed."
    end

    ensure_safe_root!
    FileUtils.rm_rf(target_dir)
    true
  end

  def zip_path(filename)
    real_root = ensure_safe_root!
    filename = normalize_filename(filename)
    song_dir = File.join(songs_root, filename)
    song_stat = lstat(song_dir)
    raise "User song '#{filename}' was not found." unless song_stat
    raise 'Unsafe song storage path.' if song_stat.symlink?
    unless song_stat.directory? && safe_real_path?(song_dir, real_root, :directory)
      raise "User song '#{filename}' was not found."
    end

    zip = File.join(song_dir, 'sounds.zip')
    zip_stat = lstat(zip)
    raise "User song '#{filename}' was not found." unless zip_stat
    raise 'Unsafe song storage path.' if zip_stat.symlink?
    unless zip_stat.file? && safe_real_path?(zip, real_root, :file)
      raise "User song '#{filename}' was not found."
    end

    zip
  end

  def installed?(filename)
    real_root = ensure_safe_root!
    song_dir = File.join(songs_root, normalize_filename(filename))
    safe_real_path?(song_dir, real_root, :directory)
  end

  def existing_song_numbers
    (built_in_song_numbers + user_song_numbers).uniq
  end

  def next_song_number
    (existing_song_numbers.max || 0) + 1
  end

  private

  def install_under_lock!(manifest, allow_public_zip_conflict)
    ensure_safe_root!
    filename = normalize_filename(manifest.filename)
    target_dir = File.join(songs_root, filename)
    raise "Song '#{filename}' is already installed." if path_entry_exists?(target_dir)

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

    tmp_dir = File.join(songs_root, ".#{filename}.tmp-#{Process.pid}-#{rand(1_000_000)}")
    FileUtils.mkdir_p(tmp_dir)

    begin
      real_root = ensure_safe_root!
      raise 'Unsafe song storage path.' unless safe_real_path?(tmp_dir, real_root, :directory)

      File.write(File.join(tmp_dir, 'song.json'), JSON.pretty_generate(data) + "\n", mode: 'w', encoding: 'UTF-8')
      FileUtils.cp(manifest.zip_path, File.join(tmp_dir, 'sounds.zip'))

      real_root = ensure_safe_root!
      raise 'Unsafe song storage path.' unless safe_real_path?(tmp_dir, real_root, :directory)
      raise "Song '#{filename}' is already installed." if path_entry_exists?(target_dir)

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

  def with_install_lock
    real_root = ensure_safe_root!
    lock_path = File.join(songs_root, '.install.lock')
    lock_stat = lstat(lock_path)
    if lock_stat && (lock_stat.symlink? || !lock_stat.file? || !safe_real_path?(lock_path, real_root, :file))
      raise 'Unsafe song storage path.'
    end

    File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      begin
        real_root = ensure_safe_root!
        raise 'Unsafe song storage path.' unless safe_real_path?(lock_path, real_root, :file)
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end
  end

  def ensure_safe_root!
    root_stat = File.lstat(songs_root)
    real_root = File.realpath(songs_root)
    expected_root = File.expand_path(songs_root)

    unless root_stat.directory? && !root_stat.symlink? && real_root == expected_root
      raise 'Unsafe song storage path.'
    end

    real_root
  rescue SystemCallError
    raise 'Unsafe song storage path.'
  end

  def safe_real_path?(path, real_root, type)
    path_stat = File.lstat(path)
    return false if path_stat.symlink?
    return false if type == :directory && !path_stat.directory?
    return false if type == :file && !path_stat.file?

    File.realpath(path).start_with?(real_root + File::SEPARATOR)
  rescue SystemCallError
    false
  end

  def path_entry_exists?(path)
    !lstat(path).nil?
  end

  def lstat(path)
    File.lstat(path)
  rescue Errno::ENOENT, Errno::ENOTDIR
    nil
  end

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
