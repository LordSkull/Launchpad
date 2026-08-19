# frozen_string_literal: true

require 'tempfile'
require Rails.root.join('script', 'song_tool').to_s
require Rails.root.join('script', 'song_store').to_s

class LocalSongsController < ApplicationController
  MAX_ZIP_BYTES = 50 * 1024 * 1024
  MAX_MANIFEST_BYTES = 1024 * 1024

  skip_before_action :verify_authenticity_token, only: [:create, :destroy]
  before_action :development_only!

  def index
    render json: {
      ok: true,
      songs: store.list
    }
  end

  def create
    manifest_json = params[:manifest].to_s
    zip_upload = params[:zip]

    if manifest_json.empty?
      return render json: { ok: false, error: 'Missing manifest JSON.' }, status: :bad_request
    end

    unless zip_upload.respond_to?(:tempfile) && zip_upload.tempfile
      return render json: { ok: false, error: 'Missing ZIP upload.' }, status: :bad_request
    end

    if manifest_json.bytesize > MAX_MANIFEST_BYTES
      return render json: { ok: false, error: 'Manifest is too large.' }, status: 413
    end

    if zip_upload.size.to_i > MAX_ZIP_BYTES
      return render json: { ok: false, error: 'ZIP is larger than 50 MB.' }, status: 413
    end

    manifest_file = Tempfile.new(['launchpad-song-', '.json'])

    begin
      manifest_file.binmode
      manifest_file.write(manifest_json)
      manifest_file.flush

      manifest = SongManifest.new(manifest_file.path, zip_upload.tempfile.path).validate!

      unless manifest.valid?
        return render json: {
          ok: false,
          error: 'Song package is invalid.',
          errors: manifest.errors,
          warnings: manifest.warnings
        }, status: :unprocessable_entity
      end

      result = store.install!(manifest)

      render json: {
        ok: true,
        message: 'Song installed successfully.',
        warnings: manifest.warnings,
        song: {
          name: manifest.data['song_name'],
          bpm: manifest.data['bpm'],
          id: result['song_number'],
          filename: result['filename'],
          manifest_path: result['manifest_path'],
          zip_path: result['zip_path']
        }
      }, status: :created
    ensure
      manifest_file.close!
    end
  rescue StandardError => e
    render_exception(e, 'Song import failed')
  end

  def destroy
    filename = params[:filename].to_s
    song = store.list.find { |item| item['filename'] == filename }
    return render json: { ok: false, error: 'Song not found.' }, status: :not_found unless song

    store.remove!(filename)
    render json: {
      ok: true,
      message: 'Song removed successfully.',
      song: { name: song['song_name'], filename: filename }
    }
  rescue StandardError => e
    render_exception(e, 'Song removal failed')
  end

  # Existing loadZip.js requests /zip/sounds/<filename>.zip.
  # Built-in ZIPs are served directly from public/. User ZIPs fall through
  # to this route and are read from user_data/songs/<filename>/sounds.zip.
  def zip
    path = store.zip_path(params[:filename].to_s)
    send_file path, type: 'application/zip', disposition: 'inline'
  rescue StandardError => e
    Rails.logger.warn("User song ZIP not found: #{e.message}")
    head :not_found
  end

  private

  def store
    @store ||= UserSongStore.new(Rails.root.to_s)
  end

  def development_only!
    head :not_found unless Rails.env.development?
  end

  def render_exception(error, prefix)
    Rails.logger.error("#{prefix}: #{error.class}: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
    render json: { ok: false, error: error.message }, status: :unprocessable_entity
  end
end
