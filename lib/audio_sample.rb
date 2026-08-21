# frozen_string_literal: true

module AudioSample
  SUPPORTED_EXTENSIONS = %w[.mp3 .wav .ogg].freeze

  def self.supported?(filename)
    SUPPORTED_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
  end

  # Legacy mappings store MP3 sample basenames without an extension.
  def self.resolve_filename(sample)
    value = sample.to_s
    supported?(value) ? value : "#{value}.mp3"
  end
end
