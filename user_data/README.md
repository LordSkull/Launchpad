# Local user songs

User-installed songs live here and are intentionally not committed.

Each installed song has this structure:

```text
user_data/songs/<filename>/
├── song.json
└── sounds.zip
```

The Rails development server exposes the ZIP through the legacy URL shape
`/zip/sounds/<filename>.zip`, so the original `loadZip.js` does not need to know
where user data is stored.
