Rails.application.routes.draw do
  root "application#index"
  
  post "/get_asset_path" => "application#getAssetUrl"
  
  #song
  
  get "/google13ecc4458e525973" => "application#google13ecc4458e525973"

# Local user-song library. Kept development-only until the Docker/local-only gate is added.
if Rails.env.development?
  get    '/dev/song_imports'           => 'local_songs#index'
  post   '/dev/song_imports'           => 'local_songs#create'
  delete '/dev/song_imports/:filename' => 'local_songs#destroy'
  get    '/zip/sounds/:filename.zip'   => 'local_songs#zip'
end
end
