require 'test_helper'
require 'tmpdir'
require 'fileutils'
require Rails.root.join('script', 'song_tool').to_s

class ZipEntriesTest < ActiveSupport::TestCase
  CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50
  EOCD_SIGNATURE = 0x06054b50
  UTF8_FLAG = 0x0800
  ENCRYPTED_FLAG = 0x0001

  def setup
    @temporary_root = Dir.mktmpdir('launchpad-zip-entries-')
    @zip_path = File.join(@temporary_root, 'test.zip')
  end

  def teardown
    FileUtils.remove_entry(@temporary_root) if @temporary_root && File.exist?(@temporary_root)
  end

  test 'reads an empty ZIP as an empty entry list' do
    assert_equal [], read_zip(archive([]))
  end

  test 'reads a single central directory filename' do
    entries = [central_directory_entry('kick.mp3')]

    assert_equal ['kick.mp3'], read_zip(archive(entries))
  end

  test 'preserves central directory order and skips extra and comment bytes' do
    entries = [
      central_directory_entry('kick.mp3', extra: 'extra', comment: 'first sample'),
      central_directory_entry('snare.mp3'),
      central_directory_entry('folder/sample.mp3')
    ]

    assert_equal ['kick.mp3', 'snare.mp3', 'folder/sample.mp3'], read_zip(archive(entries))
  end

  test 'returns directory entries' do
    entries = [central_directory_entry('samples/')]

    assert_equal ['samples/'], read_zip(archive(entries))
  end

  test 'normalizes backslashes in entry names' do
    entries = [central_directory_entry('folder\\sample.mp3')]

    assert_equal ['folder/sample.mp3'], read_zip(archive(entries))
  end

  test 'preserves duplicate entry names' do
    entries = [
      central_directory_entry('kick.mp3'),
      central_directory_entry('kick.mp3')
    ]

    assert_equal ['kick.mp3', 'kick.mp3'], read_zip(archive(entries))
  end

  test 'returns parent traversal and absolute path-like names unchanged' do
    entries = [
      central_directory_entry('../evil.mp3'),
      central_directory_entry('/absolute.mp3')
    ]

    assert_equal ['../evil.mp3', '/absolute.mp3'], read_zip(archive(entries))
  end

  test 'decodes a valid UTF-8 flagged filename' do
    entries = [central_directory_entry('caffè.mp3', flags: UTF8_FLAG)]

    result = read_zip(archive(entries)).first

    assert_equal 'caffè.mp3', result
    assert_equal Encoding::UTF_8, result.encoding
    assert_predicate result, :valid_encoding?
  end

  test 'scrubs invalid bytes in a UTF-8 flagged filename' do
    invalid_name = "bad-\xFF.mp3".b
    entries = [central_directory_entry(invalid_name, flags: UTF8_FLAG)]

    result = read_zip(archive(entries)).first

    assert_equal "bad-\uFFFD.mp3", result
    assert_equal Encoding::UTF_8, result.encoding
    assert_predicate result, :valid_encoding?
  end

  test 'rejects empty and non-ZIP input when EOCD is absent' do
    ['', 'not a ZIP'].each do |bytes|
      error = assert_raises(RuntimeError) { read_zip(bytes.b) }

      assert_match(/EOCD not found/, error.message)
    end
  end

  test 'a truncated EOCD currently raises NoMethodError' do
    bytes = [EOCD_SIGNATURE].pack('V')

    assert_raises(NoMethodError) { read_zip(bytes) }
  end

  test 'rejects a truncated central directory header' do
    truncated_directory = [CENTRAL_DIRECTORY_SIGNATURE].pack('V') + ("\x00" * 6)
    bytes = truncated_directory + eocd_record(
      entries_on_disk: 1,
      total_entries: 1,
      central_directory_size: 46,
      central_directory_offset: 0
    )

    error = assert_raises(RuntimeError) { read_zip(bytes) }

    assert_match(/Invalid central directory/, error.message)
  end

  test 'rejects an unexpected central directory signature' do
    entries = [central_directory_entry('kick.mp3', signature: 0xDEADBEEF)]

    error = assert_raises(RuntimeError) { read_zip(archive(entries)) }

    assert_match(/Unexpected ZIP central-directory signature/, error.message)
  end

  test 'an offset beyond EOF fails during central directory parsing' do
    entries = [central_directory_entry('kick.mp3')]

    error = assert_raises(RuntimeError) do
      read_zip(archive(entries, central_directory_offset: 4096))
    end

    assert_match(/Invalid central directory at byte 4096/, error.message)
  end

  test 'a central directory size larger than its data fails after parsed entries' do
    entry = central_directory_entry('kick.mp3')

    error = assert_raises(RuntimeError) do
      read_zip(archive([entry], central_directory_size: entry.bytesize + 1))
    end

    assert_match(/Invalid central directory/, error.message)
  end

  test 'rejects ZIP64 central directory size and offset sentinels' do
    [
      { central_directory_size: 0xFFFFFFFF },
      { central_directory_offset: 0xFFFFFFFF }
    ].each do |override|
      error = assert_raises(RuntimeError) do
        read_zip(archive([], **override))
      end

      assert_equal 'ZIP64 archives are not supported by this MVP', error.message
    end
  end

  test 'ignores EOCD entry counts and follows central directory size' do
    entries = [central_directory_entry('actual.mp3')]

    result = read_zip(
      archive(entries, entries_on_disk: 0, total_entries: 9)
    )

    assert_equal ['actual.mp3'], result
  end

  test 'ignores compressed and uncompressed size metadata' do
    entries = [
      central_directory_entry(
        'metadata-only.mp3',
        compressed_size: 0xFFFFFFF0,
        uncompressed_size: 0xFFFFFFF1,
        local_header_offset: 0xFFFFFFF2
      )
    ]

    assert_equal ['metadata-only.mp3'], read_zip(archive(entries))
  end

  test 'ignores encryption and compression method metadata' do
    entries = [
      central_directory_entry(
        'encrypted-unknown-method.mp3',
        flags: ENCRYPTED_FLAG,
        compression_method: 99
      )
    ]

    assert_equal ['encrypted-unknown-method.mp3'], read_zip(archive(entries))
  end

  private

  def read_zip(bytes)
    File.binwrite(@zip_path, bytes)
    ZipEntries.read(@zip_path)
  end

  def archive(entries, entries_on_disk: nil, total_entries: nil,
              central_directory_size: nil, central_directory_offset: 0)
    central_directory = entries.join.b
    actual_count = entries.length

    central_directory + eocd_record(
      entries_on_disk: entries_on_disk.nil? ? actual_count : entries_on_disk,
      total_entries: total_entries.nil? ? actual_count : total_entries,
      central_directory_size: central_directory_size.nil? ? central_directory.bytesize : central_directory_size,
      central_directory_offset: central_directory_offset
    )
  end

  def central_directory_entry(filename, flags: 0, compression_method: 0,
                              compressed_size: 0, uncompressed_size: 0,
                              extra: '', comment: '', local_header_offset: 0,
                              signature: CENTRAL_DIRECTORY_SIGNATURE)
    name_bytes = binary(filename)
    extra_bytes = binary(extra)
    comment_bytes = binary(comment)

    header = [
      signature,
      20,
      20,
      flags,
      compression_method,
      0,
      0,
      0,
      compressed_size,
      uncompressed_size,
      name_bytes.bytesize,
      extra_bytes.bytesize,
      comment_bytes.bytesize,
      0,
      0,
      0,
      local_header_offset
    ].pack('VvvvvvvVVVvvvvvVV')

    header + name_bytes + extra_bytes + comment_bytes
  end

  def eocd_record(entries_on_disk:, total_entries:, central_directory_size:,
                  central_directory_offset:)
    [
      EOCD_SIGNATURE,
      0,
      0,
      entries_on_disk,
      total_entries,
      central_directory_size,
      central_directory_offset,
      0
    ].pack('VvvvvVVv')
  end

  def binary(value)
    value.dup.force_encoding(Encoding::BINARY)
  end
end
