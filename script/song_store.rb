# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tmpdir'

class UserSongStore
  attr_reader :repo_root, :songs_root

  class VerifiedZip
    CHUNK_SIZE = 64 * 1024

    attr_reader :last_modified, :size

    def initialize(io, size, last_modified)
      @io = io
      @size = size
      @last_modified = last_modified
    end

    def each
      return enum_for(:each) unless block_given?

      begin
        while (chunk = @io.read(CHUNK_SIZE))
          yield chunk
        end
      ensure
        close
      end
    end

    def close
      @io.close unless @io.closed?
    end

    def closed?
      @io.closed?
    end
  end

  def initialize(repo_root)
    @repo_root = File.expand_path(repo_root)
    @songs_root = File.join(@repo_root, 'user_data', 'songs')
    create_safe_root!
    ensure_safe_root!
  end

  def list
    real_root = ensure_safe_root!

    Dir.entries(songs_root).sort.each_with_object([]) do |entry, songs|
      next if entry == '.' || entry == '..' || entry.start_with?('.')
      next unless valid_filename?(entry)
      song_dir = File.join(songs_root, entry)
      next unless safe_real_path?(song_dir, real_root, :directory)

      manifest_path = File.join(song_dir, 'song.json')
      next unless safe_real_path?(manifest_path, real_root, :file)

      zip_path = File.join(song_dir, 'sounds.zip')
      next unless safe_real_path?(zip_path, real_root, :file)

      begin
        data = open_verified_regular_file(manifest_path, real_root) do |manifest_file|
          JSON.parse(manifest_file.read)
        end
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
    FileUtils.remove_entry_secure(target_dir, true)
    true
  end

  def zip_path(filename)
    validated_zip_entry(filename).first
  end

  def open_zip(filename)
    zip, expected_stat = validated_zip_entry(filename)
    io = File.open(zip, 'rb')
    opened_stat = io.stat
    raise 'Unsafe song storage path.' unless same_file?(expected_stat, opened_stat)

    verified_zip = VerifiedZip.new(io, opened_stat.size, opened_stat.mtime)
    io = nil
    verified_zip
  ensure
    io.close if defined?(io) && io && !io.closed?
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

  def validated_zip_entry(filename)
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

    [zip, zip_stat]
  end

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

    tmp_dir = Dir.mktmpdir(".#{filename}.tmp-", songs_root)

    begin
      real_root = ensure_safe_root!
      raise 'Unsafe song storage path.' unless safe_real_path?(tmp_dir, real_root, :directory)

      create_exclusive_file(File.join(tmp_dir, 'song.json')) do |manifest_file|
        manifest_file.write(JSON.pretty_generate(data) + "\n")
      end
      create_exclusive_file(File.join(tmp_dir, 'sounds.zip')) do |zip_file|
        File.open(manifest.zip_path, 'rb') { |source| IO.copy_stream(source, zip_file) }
      end

      real_root = ensure_safe_root!
      raise 'Unsafe song storage path.' unless safe_real_path?(tmp_dir, real_root, :directory)
      raise "Song '#{filename}' is already installed." if path_entry_exists?(target_dir)

      FileUtils.mv(tmp_dir, target_dir)
    rescue StandardError
      remove_entry_secure(tmp_dir)
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
    lock = open_install_lock(lock_path, real_root)
    begin
      lock.flock(File::LOCK_EX)
      begin
        real_root = ensure_safe_root!
        lock_stat = lstat(lock_path)
        unless safe_regular_entry?(lock_path, real_root, lock_stat) && same_file?(lock_stat, lock.stat)
          raise 'Unsafe song storage path.'
        end
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    ensure
      lock.close
    end
  end

  def open_install_lock(lock_path, real_root)
    loop do
      lock_stat = lstat(lock_path)
      if lock_stat
        raise 'Unsafe song storage path.' unless safe_regular_entry?(lock_path, real_root, lock_stat)

        lock = File.open(lock_path, File::RDWR)
        unless same_file?(lock_stat, lock.stat)
          lock.close
          raise 'Unsafe song storage path.'
        end
        return lock
      end

      begin
        lock = File.open(lock_path, File::RDWR | File::CREAT | File::EXCL, 0o600)
        created_stat = lstat(lock_path)
        unless safe_regular_entry?(lock_path, real_root, created_stat) && same_file?(created_stat, lock.stat)
          lock.close
          raise 'Unsafe song storage path.'
        end
        return lock
      rescue Errno::EEXIST
        next
      end
    end
  rescue SystemCallError
    lock.close if defined?(lock) && lock && !lock.closed?
    raise 'Unsafe song storage path.'
  end

  def create_safe_root!
    missing = []
    path = songs_root

    while lstat(path).nil?
      missing << path
      parent = File.dirname(path)
      raise 'Unsafe song storage path.' if parent == path
      path = parent
    end

    ensure_safe_existing_directory!(path)
    missing.reverse_each do |directory|
      begin
        Dir.mkdir(directory)
      rescue Errno::EEXIST
        # Another cooperative initializer may have created it.
      end
      ensure_safe_existing_directory!(directory)
    end
  end

  def ensure_safe_existing_directory!(path)
    path_stat = File.lstat(path)
    expected = File.expand_path(path)
    unless path_stat.directory? && !path_stat.symlink? && File.realpath(path) == expected
      raise 'Unsafe song storage path.'
    end
  rescue SystemCallError
    raise 'Unsafe song storage path.'
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

  def safe_regular_entry?(path, real_root, path_stat)
    path_stat && !path_stat.symlink? && path_stat.file? &&
      File.realpath(path).start_with?(real_root + File::SEPARATOR)
  rescue SystemCallError
    false
  end

  def same_file?(expected_stat, actual_stat)
    expected_stat && actual_stat && expected_stat.file? && actual_stat.file? &&
      expected_stat.dev == actual_stat.dev && expected_stat.ino == actual_stat.ino
  end

  def open_verified_regular_file(path, real_root)
    expected_stat = lstat(path)
    return nil unless safe_regular_entry?(path, real_root, expected_stat)

    File.open(path, File::RDONLY, encoding: 'UTF-8') do |file|
      return nil unless same_file?(expected_stat, file.stat)
      yield file
    end
  rescue SystemCallError
    nil
  end

  def create_exclusive_file(path)
    File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      yield file
    end
  end

  def remove_entry_secure(path)
    FileUtils.remove_entry_secure(path, true) if path_entry_exists?(path)
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
    filename = value.to_s
    unless valid_filename?(filename)
      raise "Invalid song filename '#{filename}'."
    end
    filename
  end

  def valid_filename?(value)
    value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]+\z/)
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
