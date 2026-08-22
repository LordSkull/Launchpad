#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../lib/audio_sample'

PAD_COUNT = 48
MIN_CHAIN_COUNT = 4
MAX_CHAIN_COUNT = 8
LEGACY_CHAIN_COUNT = 4
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
    validate_chain_count
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

  def effective_chain_count
    return LEGACY_CHAIN_COUNT unless data.key?('chain_count')

    count = data['chain_count']
    count.is_a?(Integer) && count.between?(MIN_CHAIN_COUNT, MAX_CHAIN_COUNT) ? count : LEGACY_CHAIN_COUNT
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

  def validate_chain_count
    return unless data.key?('chain_count')

    count = data['chain_count']
    return if count.is_a?(Integer) && count.between?(MIN_CHAIN_COUNT, MAX_CHAIN_COUNT)

    errors << "chain_count must be an integer between #{MIN_CHAIN_COUNT} and #{MAX_CHAIN_COUNT}"
  end

  def validate_mappings
    mappings = data['mappings']
    unless mappings.is_a?(Hash)
      errors << "mappings must be an object containing chain1..chain#{effective_chain_count}"
      return
    end

    validate_chain_keys(mappings, 'mappings')
    chains.each do |chain|
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
        if sample.include?('/') || sample.include?('\\')
          errors << "mappings.#{chain}[#{i}] must be a sample filename only (example: kick.wav, not path/kick.wav)"
        end
      end
    end
  end

  def validate_hold_to_play
    holds = data['holdToPlay']
    unless holds.is_a?(Hash)
      errors << "holdToPlay must be an object containing chain1..chain#{effective_chain_count}"
      return
    end

    validate_chain_keys(holds, 'holdToPlay')
    chains.each do |chain|
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
      errors << "linkedAreas must be an object containing chain1..chain#{effective_chain_count}"
      return
    end

    validate_chain_keys(linked, 'linkedAreas')
    chains.each do |chain|
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

  def chains
    (1..effective_chain_count).map { |number| "chain#{number}" }
  end

  def validate_chain_keys(section, label)
    allowed = chains
    section.each_key do |key|
      next unless key.to_s.match?(/\Achain\d+\z/)
      next if allowed.include?(key)

      errors << "#{label}.#{key} is not allowed for chain_count #{effective_chain_count}"
    end
  end

  def validate_zip_references
    files = entries.reject { |e| e.end_with?('/') }
    mappings = data['mappings']
    return unless mappings.is_a?(Hash)

    used = []
    chains.each do |chain|
      arr = mappings[chain]
      next unless arr.is_a?(Array)
      arr.each_with_index do |sample, pad|
        next unless sample.is_a?(String) && !sample.empty?
        expected = "sounds/#{chain}/#{AudioSample.resolve_filename(sample)}"
        used << expected
        errors << "Missing ZIP entry for #{chain} pad #{pad} (#{KEY_LABELS[pad]}): #{expected}" unless files.include?(expected)
      end
    end

    audio_files = files.select do |entry|
      match = entry.match(/\Asounds\/chain(\d+)\//)
      match && match[1].to_i.between?(1, effective_chain_count) && AudioSample.supported?(entry)
    end
    unused = audio_files - used
    warnings << "#{unused.length} supported audio file(s) in the ZIP are not mapped to any pad" if unused.any?

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

require_relative 'song_store'

class Installer
  def initialize(manifest, repo_root)
    @manifest = manifest
    @repo_root = File.expand_path(repo_root)
  end

  def install!
    result = UserSongStore.new(@repo_root).install!(@manifest)

    puts "Installed successfully in user_data:"
    puts "  Manifest: #{result['manifest_path']}"
    puts "  ZIP:      #{result['zip_path']}"
    puts "  ID:       #{result['song_number']}"
    puts
    puts 'Reload the Launchpad page to see the new song.'

    result
  end
end

def usage!
  warn <<~TEXT
    Usage:
      bundle exec ruby script/song_tool.rb validate PATH_TO/song.json PATH_TO/sounds.zip
      bundle exec ruby script/song_tool.rb install  PATH_TO/song.json PATH_TO/sounds.zip

    User songs are stored under user_data/songs/. The install command must be run from inside the Launchpad repository.
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
  puts "  ID:   #{manifest.song_number || '(auto on install)'}"

  Installer.new(manifest, Dir.pwd).install! if command == 'install'
end
