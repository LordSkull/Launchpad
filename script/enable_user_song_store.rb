#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'tempfile'
require_relative 'song_tool'
require_relative 'song_store'

repo_root = File.expand_path('..', __dir__)
application_js = File.join(repo_root, 'app', 'assets', 'javascripts', 'application.js')
keyboard_js = File.join(repo_root, 'app', 'assets', 'javascripts', 'keyboard.js')
routes_rb = File.join(repo_root, 'config', 'routes.rb')
index_view = File.join(repo_root, 'app', 'views', 'application', 'index.html.erb')

[application_js, keyboard_js, routes_rb, index_view].each do |path|
  abort "Missing required file: #{path}" unless File.file?(path)
end

def backup(path, suffix)
  destination = path + suffix
  FileUtils.cp(path, destination) unless File.exist?(destination)
  destination
end

backup(application_js, '.before_user_songs_v2')
backup(keyboard_js, '.before_user_songs_v2')
backup(routes_rb, '.before_user_songs_v2')
backup(index_view, '.before_user_songs_v2')

store = UserSongStore.new(repo_root)
keyboard_text = File.read(keyboard_js, encoding: 'UTF-8')
legacy_vars_migrated = []

# Migrate songs installed by the previous tool. Its generated files always used data_<variable>.js.
Dir.glob(File.join(repo_root, 'app', 'assets', 'javascripts', 'data_*.js')).sort.each do |data_path|
  text = File.read(data_path, encoding: 'UTF-8')
  match = text.match(/\A\s*var\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*(\{.*\})\s*;?\s*\z/m)
  unless match
    warn "Skipping legacy file with unrecognized format: #{data_path}"
    next
  end

  variable_name = match[1]
  begin
    data = JSON.parse(match[2])
  rescue JSON::ParserError => e
    warn "Skipping #{data_path}: #{e.message}"
    next
  end

  filename = data['filename'].to_s
  source_zip = File.join(repo_root, 'public', 'zip', 'sounds', "#{filename}.zip")
  unless File.file?(source_zip)
    warn "Skipping #{data_path}: missing #{source_zip}"
    next
  end

  if store.installed?(filename)
    warn "Skipping migration for #{filename}: already exists in user_data."
    next
  end

  temp = Tempfile.new(['legacy-song-', '.json'])
  begin
    data['variable_name'] = variable_name
    temp.write(JSON.pretty_generate(data))
    temp.flush
    manifest = SongManifest.new(temp.path, source_zip).validate!
    unless manifest.valid?
      warn "Skipping migration for #{filename}: #{manifest.errors.join('; ')}"
      next
    end

    store.install!(manifest, true)
    FileUtils.rm_f(data_path)
    FileUtils.rm_f(source_zip)
    legacy_vars_migrated << variable_name
    puts "Migrated legacy user song: #{filename}"
  ensure
    temp.close!
  end
end

# Remove migrated variables from the old hard-coded list, then make the list permanently data-driven.
keyboard_text = File.read(keyboard_js, encoding: 'UTF-8')
match = keyboard_text.match(/var\s+songDatas\s*=\s*\[([^\]]*)\](?:\.concat\(window\.userSongDatas\s*\|\|\s*\[\]\))?\s*;/)
abort 'Could not find var songDatas = [...] in keyboard.js' unless match
vars = match[1].split(',').map(&:strip).reject(&:empty?)
vars -= legacy_vars_migrated
replacement = "var songDatas = [#{vars.join(', ')}].concat(window.userSongDatas || []);"
keyboard_text.sub!(match[0], replacement)
File.write(keyboard_js, keyboard_text, mode: 'w', encoding: 'UTF-8')

# Ensure the user-song catalog is loaded before require_tree reaches keyboard.js.
app_text = File.read(application_js, encoding: 'UTF-8')
unless app_text.include?('//= require 00_user_songs')
  marker = '//= require_tree .'
  if app_text.include?(marker)
    app_text.sub!(marker, "//= require 00_user_songs\n#{marker}")
  else
    app_text << "\n//= require 00_user_songs\n"
  end
  File.write(application_js, app_text, mode: 'w', encoding: 'UTF-8')
end

# Replace the previous development installer route with install/list/remove + ZIP serving.
routes_text = File.read(routes_rb, encoding: 'UTF-8')
routes_text.gsub!(/\n\s*# Local song installer\..*?\n\s*if Rails\.env\.development\?\s*\n\s*post ['\"]\/dev\/song_imports['\"]\s*=>\s*['\"]song_imports#create['\"]\s*\n\s*end\s*\n/m, "\n")

route_marker = "get '/dev/song_imports' => 'local_songs#index'"
unless routes_text.include?(route_marker)
  block = <<~ROUTES

    # Local user-song library. Kept development-only until the Docker/local-only gate is added.
    if Rails.env.development?
      get    '/dev/song_imports'           => 'local_songs#index'
      post   '/dev/song_imports'           => 'local_songs#create'
      delete '/dev/song_imports/:filename' => 'local_songs#destroy'
      get    '/zip/sounds/:filename.zip'   => 'local_songs#zip'
    end
  ROUTES

  last_end = routes_text.rindex(/^end\s*$/)
  abort 'Could not find final end in config/routes.rb' unless last_end
  routes_text.insert(last_end, block)
end
File.write(routes_rb, routes_text, mode: 'w', encoding: 'UTF-8')

# Add visible navigation to the existing home without depending on its legacy layout.
index_text = File.read(index_view, encoding: 'UTF-8')
unless index_text.include?('id="local-song-tools"')
  index_text << <<~HTML

    <!-- Local song tools -->
    <div id="local-song-tools" style="position:fixed;top:12px;right:12px;z-index:10000;display:flex;gap:8px;">
      <a href="/song_builder.html" data-turbolinks="false" style="padding:8px 12px;background:#fff;color:#222;border:1px solid #555;text-decoration:none;">+ Add Song</a>
      <a href="/manage_songs.html" data-turbolinks="false" style="padding:8px 12px;background:#fff;color:#222;border:1px solid #555;text-decoration:none;">Manage Songs</a>
    </div>
  HTML
  File.write(index_view, index_text, mode: 'w', encoding: 'UTF-8')
end

# Keep personal song data out of git, while retaining the directory skeleton.
gitignore = File.join(repo_root, '.gitignore')
gitignore_text = File.exist?(gitignore) ? File.read(gitignore, encoding: 'UTF-8') : ''
ignore_block = "\n# User-installed Launchpad songs\n/user_data/songs/*\n!/user_data/songs/.gitkeep\n"
unless gitignore_text.include?('/user_data/songs/*')
  File.write(gitignore, gitignore_text + ignore_block, mode: 'w', encoding: 'UTF-8')
end
FileUtils.mkdir_p(File.join(repo_root, 'user_data', 'songs'))
FileUtils.touch(File.join(repo_root, 'user_data', 'songs', '.gitkeep'))

puts
puts 'User-song store enabled.'
puts "Migrated #{legacy_vars_migrated.length} legacy installed song(s)."
puts 'User songs now live under user_data/songs/<filename>/.'
puts 'Restart Rails and hard-refresh the home page.'
