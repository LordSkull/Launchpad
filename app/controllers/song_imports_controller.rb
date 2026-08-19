# frozen_string_literal: true

require 'tempfile'
require Rails.root.join('script', 'song_tool').to_s

class SongImportsController < ApplicationController
  MAX_ZIP_BYTES = 50 * 1024 * 1024
  MAX_MANIFEST_BYTES = 1024 * 1024

  skip_before_action :verify_authenticity_token, only: :create
  before_action :development_only!

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

      result = Installer.new(manifest, Rails.root.to_s).install!

      render json: {
        ok: true,
        message: 'Song installed successfully.',
        warnings: manifest.warnings,
        song: {
          name: manifest.data['song_name'],
          bpm: manifest.data['bpm'],
          id: result['song_number'],
          variable_name: result['variable_name'],
          data_path: result['data_path'],
          zip_path: result['zip_path']
        }
      }, status: :created
    ensure
      manifest_file.close!
    end
  rescue StandardError => e
    Rails.logger.error("Song import failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace

    render json: {
      ok: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  private

  def development_only!
    head :not_found unless Rails.env.development?
  end
end
