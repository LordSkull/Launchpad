#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'

repo_root = File.expand_path('..', __dir__)
routes_path = File.join(repo_root, 'config', 'routes.rb')
route_marker = "post '/dev/song_imports' => 'song_imports#create'"
route_block = <<~ROUTES

  # Local song installer. Intentionally unavailable outside development.
  if Rails.env.development?
    post '/dev/song_imports' => 'song_imports#create'
  end
ROUTES

abort "Missing #{routes_path}" unless File.file?(routes_path)

text = File.read(routes_path, encoding: 'UTF-8')

if text.include?(route_marker)
  puts 'Song web-installer route is already enabled.'
  exit 0
end

last_end = text.rindex(/^end\s*$/)
abort 'Could not find the final `end` in config/routes.rb.' unless last_end

backup = routes_path + '.before_song_installer'
FileUtils.cp(routes_path, backup) unless File.exist?(backup)

text.insert(last_end, route_block)
File.write(routes_path, text, mode: 'w', encoding: 'UTF-8')

puts 'Enabled POST /dev/song_imports in development.'
puts "Backup: #{backup}"
