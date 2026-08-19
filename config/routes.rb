Rails.application.routes.draw do
  root "application#index"
  
  post "/get_asset_path" => "application#getAssetUrl"
  
  post "/login" => "application#login"
  get "/logout" => "application#logout"
  
  #song
  post "/create_song" => "song#create"
  post "/view_all_songs" => "song#view_all"
  
  get "/google13ecc4458e525973" => "application#google13ecc4458e525973"

# Local user-song library. Kept development-only until the Docker/local-only gate is added.
if Rails.env.development?
  get    '/dev/song_imports'           => 'local_songs#index'
  post   '/dev/song_imports'           => 'local_songs#create'
  delete '/dev/song_imports/:filename' => 'local_songs#destroy'
  get    '/zip/sounds/:filename.zip'   => 'local_songs#zip'
end
end
