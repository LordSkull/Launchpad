# Enable the browser “Install Song” button

These files add a development-only Rails endpoint used by `public/song_builder.html`.

## Files to copy into the Launchpad repository

Copy/overwrite these paths:

- `public/song_builder.html`
- `public/song_builder.js`
- `script/song_tool.rb`
- `script/enable_song_web_installer.rb`
- `app/controllers/song_imports_controller.rb`

## Enable the route

From the Launchpad repository root:

```powershell
bundle _1.17.3_ exec ruby script/enable_song_web_installer.rb
```

The helper backs up `config/routes.rb` as `config/routes.rb.before_song_installer` and adds this route inside the routes block:

```ruby
if Rails.env.development?
  post '/dev/song_imports' => 'song_imports#create'
end
```

## Restart Rails

```powershell
bundle _1.17.3_ exec rails s
```

Open:

```text
http://localhost:3000/song_builder.html
```

Configure a song, click `Validate`, then `Install Song`.

The server validates the manifest and ZIP again before modifying the repository. The endpoint exists only in the Rails `development` environment and rejects ZIPs larger than 50 MB.
