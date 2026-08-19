# Launchpad Add Song MVP

This adds two tools without changing the existing Launchpad runtime architecture:

1. `public/song_builder.html` + `public/song_builder.js`: browser UI for mapping a prepared ZIP to 48 pads × 4 chains and exporting `song.json`.
2. `script/song_tool.rb`: validates the JSON against the ZIP and installs the song automatically.

## Install the tools

Copy the included `public/` and `script/` files into the same directories of the Launchpad repository.

Restart Rails if needed, then open:

    http://localhost:3000/song_builder.html

## Expected sound ZIP structure

    sounds/
      chain1/
        kick.mp3
        snare.mp3
      chain2/
      chain3/
      chain4/

The names selected in the builder are stored without `.mp3` and become paths such as:

    sounds/chain2/kick.mp3

## Validate

From the Launchpad repository root:

    bundle _1.17.3_ exec ruby script/song_tool.rb validate C:\path\my_song.song.json C:\path\my_song.zip

## Install

    bundle _1.17.3_ exec ruby script/song_tool.rb install C:\path\my_song.song.json C:\path\my_song.zip

The installer:

- validates 48 mappings for each of 4 chains;
- checks every referenced MP3 exists in the ZIP;
- validates `holdToPlay` and `linkedAreas` indices;
- assigns the next `song_number` if the JSON leaves it blank;
- copies the ZIP to `public/zip/sounds/<filename>.zip`;
- creates `app/assets/javascripts/data_<variable_name>.js` (the `data_` prefix keeps Sprockets load order before `keyboard.js`);
- appends the variable to `songDatas` in `keyboard.js`.

It refuses to overwrite an existing song.

## Current MVP limitations

- The ZIP must already exist; the browser tool does not create audio ZIPs.
- ZIP64 archives are not supported.
- Linked groups are entered as pad labels, one group per line, e.g. `1,Q,A,Z`.
- This is a local developer/import workflow, not a public multi-user upload endpoint.

## Browser install button

The updated builder can install a validated song directly into the local repository. Enable the development-only endpoint with:

```powershell
bundle _1.17.3_ exec ruby script/enable_song_web_installer.rb
```

Then restart Rails and use **Install Song** in `/song_builder.html`.
