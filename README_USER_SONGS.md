# User Songs v2 — install, manage, remove without editing source code

This replaces the first-generation installer that generated `data_*.js`, copied ZIPs into `public/zip/sounds`, and edited `keyboard.js` for every song.

## Apply

Copy this package over the Launchpad repository root, then run:

```powershell
bundle _1.17.3_ exec ruby script/enable_user_song_store.rb
```

The migration script:

- backs up `application.js`, `keyboard.js`, `routes.rb`, and `index.html.erb`;
- migrates old `data_*.js` songs installed by the previous tool into `user_data/songs/`;
- removes their old hard-coded registrations;
- changes `keyboard.js` once to append `window.userSongDatas`;
- loads the user-song catalog before the legacy keyboard initializes;
- adds Add Song and Manage Songs links to the home;
- adds install/list/remove endpoints and a ZIP-serving fallback;
- ignores personal `user_data/songs/*` content in Git.

Then restart Rails:

```powershell
bundle _1.17.3_ exec rake tmp:cache:clear
bundle _1.17.3_ exec rails s
```

Open:

- Launchpad: `http://localhost:3000/`
- Add Song: `http://localhost:3000/song_builder.html`
- Manage Songs: `http://localhost:3000/manage_songs.html`

## Storage

```text
user_data/songs/my_song/
├── song.json
└── sounds.zip
```

Installing/removing a song no longer modifies `keyboard.js` or creates JavaScript source files.

## Current limitation

The local-song HTTP endpoints are still `development`-only. Before Docker/release packaging, replace this with an explicit local-only feature gate so the same mechanism works in the packaged runtime without exposing an upload/delete API publicly.
