#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'

PAD_COUNT = 48
CHAINS = (1..4).map { |n| "chain#{n}" }.freeze
KEY_LABELS = [
  '1','2','3','4','5','6','7','8','9','0','-','=',
  'Q','W','E','R','T','Y','U','I','O','P','[',']',
  'A','S','D','F','G','H','J','K','L',';','\'','ENTER',
  'Z','X','C','V','B','N','M',',','.','/','SHIFT','NA'
].freeze

class ZipEntries
  EOCD_SIG = [0x06054b50].pack('V')
  CEN_SIG = 0x02014b50

  def self.read(path)
    data = File.binread(path)
    tail_start = [data.bytesize - 65_557, 0].max
    eocd_at = data.rindex(EOCD_SIG, data.bytesize - 1)
    raise "Not a supported ZIP file (EOCD not found): #{path}" unless eocd_at && eocd_at >= tail_start

    eocd = data.byteslice(eocd_at, 22)
    cd_size = eocd.byteslice(12, 4).unpack1('V')
    cd_offset = eocd.byteslice(16, 4).unpack1('V')
    raise 'ZIP64 archives are not supported by this MVP' if cd_size == 0xFFFFFFFF || cd_offset == 0xFFFFFFFF

    entries = []
    pos = cd_offset
    finish = cd_offset + cd_size

    while pos < finish
      header = data.byteslice(pos, 46)
      raise "Invalid central directory at byte #{pos}" unless header && header.bytesize == 46
      sig = header.byteslice(0, 4).unpack1('V')
      raise "Unexpected ZIP central-directory signature at byte #{pos}" unless sig == CEN_SIG

      flags = header.byteslice(8, 2).unpack1('v')
      name_len = header.byteslice(28, 2).unpack1('v')
      extra_len = header.byteslice(30, 2).unpack1('v')
      comment_len = header.byteslice(32, 2).unpack1('v')
      raw_name = data.byteslice(pos + 46, name_len)

      name = if (flags & 0x0800) != 0
               raw_name.force_encoding(Encoding::UTF_8).scrub
             else
               raw_name.force_encoding(Encoding::BINARY).encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
             end
      entries << name.tr('\\', '/')
      pos += 46 + name_len + extra_len + comment_len
    end

    entries
  end
end

class SongManifest
  attr_reader :data, :entries, :errors, :warnings, :zip_path

  def initialize(json_path, zip_path)
    @json_path = File.expand_path(json_path)
    @zip_path = File.expand_path(zip_path)
    @errors = []
    @warnings = []
    @data = JSON.parse(File.read(@json_path, encoding: 'UTF-8'))
    @entries = ZipEntries.read(@zip_path)
  rescue JSON::ParserError => e
    @data = {}
    @entries = []
    @errors = ["Invalid JSON: #{e.message}"]
  rescue StandardError => e
    @data ||= {}
    @entries ||= []
    @errors ||= []
    @errors << e.message
  end

  def validate!
    return self unless errors.empty?

    validate_metadata
    validate_mappings
    validate_hold_to_play
    validate_linked_areas
    validate_zip_references
    self
  end

  def valid?
    errors.empty?
  end

  def filename
    data['filename'].to_s
  end

  def variable_name
    candidate = data['variable_name'].to_s.strip
    candidate = camelize(filename) + 'Data' if candidate.empty?
    candidate
  end

  def song_number
    value = data['song_number']
    return nil if value.nil? || value.to_s.strip.empty?
    Integer(value)
  rescue ArgumentError, TypeError
    nil
  end

  private

  def validate_metadata
    name = data['song_name'].to_s.strip
    errors << 'song_name is required' if name.empty?

    bpm = begin
      Float(data['bpm'])
    rescue ArgumentError, TypeError
      nil
    end
    errors << 'bpm must be a positive number' unless bpm && bpm.positive?

    if filename.empty?
      errors << 'filename is required'
    elsif filename !~ /\A[A-Za-z0-9_-]+\z/
      errors << 'filename may contain only letters, numbers, _ and -'
    end

    unless variable_name.match?(/\A[A-Za-z_$][A-Za-z0-9_$]*\z/)
      errors << "variable_name '#{variable_name}' is not a valid JavaScript variable name"
    end

    raw_number = data['song_number']
    unless raw_number.nil? || raw_number.to_s.strip.empty?
      n = song_number
      errors << 'song_number must be a positive integer when supplied' unless n && n.positive?
    end
  end

  def validate_mappings
    mappings = data['mappings']
    unless mappings.is_a?(Hash)
      errors << 'mappings must be an object containing chain1..chain4'
      return
    end

    CHAINS.each do |chain|
      arr = mappings[chain]
      unless arr.is_a?(Array)
        errors << "mappings.#{chain} must be an array"
        next
      end
      errors << "mappings.#{chain} must contain exactly #{PAD_COUNT} entries (found #{arr.length})" unless arr.length == PAD_COUNT

      arr.each_with_index do |sample, i|
        next if sample == ''
        unless sample.is_a?(String)
          errors << "mappings.#{chain}[#{i}] must be a string"
          next
        end
        if sample.include?('/') || sample.include?('\\') || sample.downcase.end_with?('.mp3')
          errors << "mappings.#{chain}[#{i}] must be a sample basename only (example: kick, not path/kick.mp3)"
        end
      end
    end
  end

  def validate_hold_to_play
    holds = data['holdToPlay']
    unless holds.is_a?(Hash)
      errors << 'holdToPlay must be an object containing chain1..chain4'
      return
    end

    CHAINS.each do |chain|
      arr = holds[chain]
      unless arr.is_a?(Array)
        errors << "holdToPlay.#{chain} must be an array"
        next
      end
      validate_indices(arr, "holdToPlay.#{chain}")
    end
  end

  def validate_linked_areas
    linked = data['linkedAreas']
    unless linked.is_a?(Hash)
      errors << 'linkedAreas must be an object containing chain1..chain4'
      return
    end

    CHAINS.each do |chain|
      groups = linked[chain]
      unless groups.is_a?(Array)
        errors << "linkedAreas.#{chain} must be an array of arrays"
        next
      end

      groups.each_with_index do |group, gi|
        unless group.is_a?(Array)
          errors << "linkedAreas.#{chain}[#{gi}] must be an array"
          next
        end
        warnings << "linkedAreas.#{chain}[#{gi}] contains fewer than 2 pads" if group.length < 2
        validate_indices(group, "linkedAreas.#{chain}[#{gi}]")
      end
    end
  end

  def validate_indices(values, label)
    seen = {}
    values.each_with_index do |value, i|
      unless value.is_a?(Integer) && value.between?(0, PAD_COUNT - 1)
        errors << "#{label}[#{i}] must be an integer between 0 and #{PAD_COUNT - 1}"
        next
      end
      warnings << "#{label} contains duplicate pad #{value}" if seen[value]
      seen[value] = true
    end
  end

  def validate_zip_references
    files = entries.reject { |e| e.end_with?('/') }
    mappings = data['mappings']
    return unless mappings.is_a?(Hash)

    used = []
    CHAINS.each_with_index do |chain, idx|
      arr = mappings[chain]
      next unless arr.is_a?(Array)
      arr.each_with_index do |sample, pad|
        next unless sample.is_a?(String) && !sample.empty?
        expected = "sounds/chain#{idx + 1}/#{sample}.mp3"
        used << expected
        errors << "Missing ZIP entry for #{chain} pad #{pad} (#{KEY_LABELS[pad]}): #{expected}" unless files.include?(expected)
      end
    end

    mp3s = files.select { |e| e.match?(/\Asounds\/chain[1-4]\/.*\.mp3\z/) }
    unused = mp3s - used
    warnings << "#{unused.length} MP3 file(s) in the ZIP are not mapped to any pad" if unused.any?

    junk = files.select { |e| e.start_with?('__MACOSX/') || File.basename(e) == '.DS_Store' }
    warnings << "ZIP contains #{junk.length} macOS metadata file(s); harmless, but removable" if junk.any?
  end

  def camelize(value)
    parts = value.split(/[^A-Za-z0-9]+/).reject(&:empty?)
    first = parts.shift.to_s
    first = "song#{first}" if first.match?(/\A\d/)
    first + parts.map { |p| p[0].to_s.upcase + p[1..].to_s }.join
  end
end

class Installer
  SONG_DATAS_RE = /var\s+songDatas\s*=\s*\[([^\]]*)\];/

  def initialize(manifest, repo_root)
    @manifest = manifest
    @repo_root = File.expand_path(repo_root)
  end

  def install!
    ensure_repo!
    number = resolved_song_number
    ensure_unique!(number)

    data = deep_copy(@manifest.data)
    data.delete('variable_name')
    data['song_number'] = number

    js_path = File.join(@repo_root, 'app', 'assets', 'javascripts', "data_#{@manifest.variable_name}.js")
    zip_path = File.join(@repo_root, 'public', 'zip', 'sounds', "#{@manifest.filename}.zip")
    keyboard_path = File.join(@repo_root, 'app', 'assets', 'javascripts', 'keyboard.js')
    keyboard_before = File.read(keyboard_path, encoding: 'UTF-8')

    raise "Refusing to overwrite existing #{js_path}" if File.exist?(js_path)
    raise "Refusing to overwrite existing #{zip_path}" if File.exist?(zip_path)

    File.write(js_path, "var #{@manifest.variable_name} = #{JSON.pretty_generate(data)};\n", mode: 'w', encoding: 'UTF-8')
    FileUtils.cp(@manifest.zip_path, zip_path)
    register_song!(keyboard_path)

    result = {
      'data_path' => relative(js_path),
      'zip_path' => relative(zip_path),
      'song_number' => number,
      'variable_name' => @manifest.variable_name
    }

    puts "Installed successfully:"
    puts "  Data: #{result['data_path']}"
    puts "  ZIP:  #{result['zip_path']}"
    puts "  ID:   #{number}"
    puts "  Var:  #{@manifest.variable_name}"
    puts
    puts 'Restart Rails (or hard-refresh in development) and test the new song.'

    result
  rescue StandardError
    FileUtils.rm_f(js_path) if defined?(js_path) && js_path && File.exist?(js_path)
    FileUtils.rm_f(zip_path) if defined?(zip_path) && zip_path && File.exist?(zip_path)
    if defined?(keyboard_before) && keyboard_before && defined?(keyboard_path) && keyboard_path
      File.write(keyboard_path, keyboard_before, mode: 'w', encoding: 'UTF-8')
    end
    raise
  end

  private

  def ensure_repo!
    required = [
      File.join(@repo_root, 'app', 'assets', 'javascripts', 'keyboard.js'),
      File.join(@repo_root, 'public', 'zip', 'sounds')
    ]
    missing = required.reject { |p| File.exist?(p) }
    raise "This does not look like the Launchpad repo: missing #{missing.join(', ')}" if missing.any?
  end

  def existing_song_numbers
    Dir.glob(File.join(@repo_root, 'app', 'assets', 'javascripts', '*.js')).map do |path|
      text = File.read(path, encoding: 'UTF-8')
      text.scan(/[\"']?song_number[\"']?\s*:\s*(\d+)/).flatten.map(&:to_i)
    rescue Encoding::InvalidByteSequenceError
      []
    end.flatten.uniq
  end

  def resolved_song_number
    @manifest.song_number || ((existing_song_numbers.max || 0) + 1)
  end

  def ensure_unique!(number)
    if existing_song_numbers.include?(number)
      raise "song_number #{number} already exists. Leave song_number blank in the builder to auto-assign, or choose a different ID."
    end

    keyboard = File.read(File.join(@repo_root, 'app', 'assets', 'javascripts', 'keyboard.js'), encoding: 'UTF-8')
    if keyboard.match?(/\b#{Regexp.escape(@manifest.variable_name)}\b/)
      raise "#{@manifest.variable_name} is already registered in keyboard.js"
    end
  end

  def register_song!(keyboard_path)
    text = File.read(keyboard_path, encoding: 'UTF-8')
    match = text.match(SONG_DATAS_RE)
    raise 'Could not find var songDatas = [...] in keyboard.js' unless match

    vars = match[1].split(',').map(&:strip).reject(&:empty?)
    vars << @manifest.variable_name
    replacement = "var songDatas = [#{vars.join(', ')}];"
    text.sub!(SONG_DATAS_RE, replacement)
    File.write(keyboard_path, text, mode: 'w', encoding: 'UTF-8')
  end

  def deep_copy(obj)
    JSON.parse(JSON.generate(obj))
  end

  def relative(path)
    path.sub(@repo_root + File::SEPARATOR, '')
  end
end

def usage!
  warn <<~TEXT
    Usage:
      bundle exec ruby script/song_tool.rb validate PATH_TO/song.json PATH_TO/sounds.zip
      bundle exec ruby script/song_tool.rb install  PATH_TO/song.json PATH_TO/sounds.zip

    The install command must be run from inside the Launchpad repository.
  TEXT
  exit 2
end

if __FILE__ == $PROGRAM_NAME
  command, json_path, zip_path = ARGV
  usage! unless %w[validate install].include?(command) && json_path && zip_path

  manifest = SongManifest.new(json_path, zip_path).validate!

  manifest.warnings.each { |w| puts "WARNING: #{w}" }
  manifest.errors.each { |e| warn "ERROR: #{e}" }

  unless manifest.valid?
    warn "\nSong package is INVALID (#{manifest.errors.length} error(s))."
    exit 1
  end

  puts "Song package is valid."
  puts "  Name: #{manifest.data['song_name']}"
  puts "  BPM:  #{manifest.data['bpm']}"
  puts "  ZIP:  #{manifest.filename}.zip"
  puts "  Var:  #{manifest.variable_name}"
  puts "  ID:   #{manifest.song_number || '(auto on install)'}"

  Installer.new(manifest, Dir.pwd).install! if command == 'install'
end
