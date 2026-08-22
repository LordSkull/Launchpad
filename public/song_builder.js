(function () {
  'use strict';

  var MIN_CHAIN_COUNT = 4;
  var MAX_CHAIN_COUNT = 8;
  var ALL_CHAINS = Array.from({ length: MAX_CHAIN_COUNT }, function (_, index) { return 'chain' + (index + 1); });
  var PAD_LABELS = [
    '1','2','3','4','5','6','7','8','9','0','-','=',
    'Q','W','E','R','T','Y','U','I','O','P','[',']',
    'A','S','D','F','G','H','J','K','L',';','\'','ENTER',
    'Z','X','C','V','B','N','M',',','.','/','SHIFT','NA'
  ];

  var state = {
    chainCount: MIN_CHAIN_COUNT,
    activeChain: 0,
    zipFile: null,
    zipEntries: [],
    zipParsedSuccessfully: false,
    samples: createChainState(function () { return []; }),
    mappings: createChainState(blank48),
    holdToPlay: createChainState(function () { return new Set(); }),
    linkedText: createChainState(function () { return ''; })
  };

  function blank48() { return Array(48).fill(''); }
  function createChainState(factory) {
    var result = {};
    ALL_CHAINS.forEach(function (chain) { result[chain] = factory(); });
    return result;
  }
  function activeChains() { return ALL_CHAINS.slice(0, state.chainCount); }
  function $(id) { return document.getElementById(id); }

  function init() {
    renderTabs();
    renderLinkedEditors();
    renderPads();

    $('zipInput').addEventListener('change', onZipSelected);
    $('chainCount').addEventListener('change', onChainCountChanged);
    $('autoFill').addEventListener('click', autoFill);
    $('clearChain').addEventListener('click', clearChain);
    $('validateBtn').addEventListener('click', function () { showValidation(validate()); });
    $('exportBtn').addEventListener('click', exportJson);
    $('installBtn').addEventListener('click', installSong);
  }

  function onChainCountChanged() {
    state.chainCount = Number($('chainCount').value);
    if (state.activeChain >= state.chainCount) state.activeChain = 0;
    renderTabs();
    renderLinkedEditors();
    renderPads();
    if (state.zipParsedSuccessfully) renderZipStatus();
  }

  function renderTabs() {
    var host = $('chainTabs');
    host.innerHTML = '';
    activeChains().forEach(function (chain, i) {
      var b = document.createElement('button');
      b.textContent = 'Chain ' + (i + 1);
      if (i === state.activeChain) b.className = 'active';
      b.addEventListener('click', function () { state.activeChain = i; renderTabs(); renderPads(); });
      host.appendChild(b);
    });
  }

  function renderLinkedEditors() {
    var host = $('linkedEditors');
    host.innerHTML = '';
    activeChains().forEach(function (chain, i) {
      var label = document.createElement('label');
      label.textContent = 'Chain ' + (i + 1) + ' linked groups';
      var ta = document.createElement('textarea');
      ta.id = 'linked-' + chain;
      ta.placeholder = '1,Q,A,Z\n2,W,S,X';
      ta.value = state.linkedText[chain];
      ta.addEventListener('input', function () { state.linkedText[chain] = this.value; });
      label.appendChild(ta);
      host.appendChild(label);
    });
  }

  function renderPads() {
    var host = $('padGrid');
    var chain = ALL_CHAINS[state.activeChain];
    var samples = state.samples[chain];
    host.innerHTML = '';

    for (var i = 0; i < 48; i++) {
      (function (padIndex) {
        var card = document.createElement('div');
        card.className = 'pad';

        var title = document.createElement('strong');
        title.textContent = PAD_LABELS[padIndex] + '  #' + padIndex;
        card.appendChild(title);

        var select = document.createElement('select');
        addOption(select, '', '(none)');
        samples.forEach(function (sample) { addOption(select, sample, sample); });
        select.value = state.mappings[chain][padIndex] || '';
        select.addEventListener('change', function () { state.mappings[chain][padIndex] = this.value; });
        card.appendChild(select);

        var hold = document.createElement('label');
        hold.className = 'hold';
        var cb = document.createElement('input');
        cb.type = 'checkbox';
        cb.checked = state.holdToPlay[chain].has(padIndex);
        cb.addEventListener('change', function () {
          if (this.checked) state.holdToPlay[chain].add(padIndex);
          else state.holdToPlay[chain].delete(padIndex);
        });
        hold.appendChild(cb);
        hold.appendChild(document.createTextNode('hold to play'));
        card.appendChild(hold);

        host.appendChild(card);
      })(i);
    }
  }

  function addOption(select, value, text) {
    var o = document.createElement('option');
    o.value = value;
    o.textContent = text;
    select.appendChild(o);
  }

  function renderZipStatus() {
    var counts = activeChains().map(function (c, i) { return 'chain' + (i + 1) + ': ' + state.samples[c].length + ' audio sample(s)'; });
    var junk = state.zipEntries.filter(function (e) { return e.indexOf('__MACOSX/') === 0 || /(^|\/)\.DS_Store$/.test(e); }).length;
    $('zipStatus').className = 'status good';
    $('zipStatus').textContent = 'ZIP read successfully.\n' + counts.join(' | ') + (junk ? '\nNote: ' + junk + ' macOS metadata entries found.' : '');
  }

  async function onZipSelected(event) {
    var file = event.target.files && event.target.files[0];
    if (!file) return;
    state.zipFile = file;
    state.zipParsedSuccessfully = false;
    $('zipStatus').textContent = 'Reading ZIP directory...';

    try {
      var entries = await listZipEntries(file);
      state.zipEntries = entries;
      state.samples = createChainState(function () { return []; });

      entries.forEach(function (entry) {
        var normalized = entry.replace(/\\/g, '/');
        var m = normalized.match(/^sounds\/chain([1-8])\/(.+)$/);
        if (m && Audio_Sample_Space.isSupported(m[2])) state.samples['chain' + m[1]].push(m[2]);
      });

      ALL_CHAINS.forEach(function (chain) {
        state.samples[chain] = unique(state.samples[chain]).sort(naturalSort);
      });

      if (!$('filename').value) {
        $('filename').value = file.name.replace(/\.zip$/i, '').replace(/[^A-Za-z0-9_-]+/g, '_');
      }

      state.zipParsedSuccessfully = true;
      renderZipStatus();
      renderPads();
    } catch (err) {
      state.zipParsedSuccessfully = false;
      $('zipStatus').className = 'status bad';
      $('zipStatus').textContent = 'Could not read ZIP: ' + err.message;
    }
  }

  function autoFill() {
    var chain = ALL_CHAINS[state.activeChain];
    state.mappings[chain] = blank48();
    state.samples[chain].slice(0, 48).forEach(function (sample, i) { state.mappings[chain][i] = sample; });
    renderPads();
  }

  function clearChain() {
    var chain = ALL_CHAINS[state.activeChain];
    state.mappings[chain] = blank48();
    state.holdToPlay[chain].clear();
    renderPads();
  }

  function buildManifest() {
    var songNumRaw = $('songNumber').value.trim();
    var mappings = cloneMappings();
    var holdToPlay = {};
    var linkedAreas = {};
    activeChains().forEach(function (chain) {
      holdToPlay[chain] = sortedNumbers(state.holdToPlay[chain]);
      linkedAreas[chain] = parseLinked(state.linkedText[chain]);
    });

    return {
      schema_version: 1,
      chain_count: state.chainCount,
      song_number: songNumRaw ? Number(songNumRaw) : null,
      song_name: $('songName').value.trim(),
      bpm: Number($('bpm').value),
      filename: $('filename').value.trim(),
      mappings: mappings,
      holdToPlay: holdToPlay,
      linkedAreas: linkedAreas
    };
  }

  function validate() {
    var data;
    var errors = [];
    var warnings = [];
    try {
      data = buildManifest();
    } catch (err) {
      return { data: null, errors: [err.message], warnings: [] };
    }

    if (!data.song_name) errors.push('Song name is required.');
    if (!(data.bpm > 0)) errors.push('BPM must be greater than 0.');
    if (!/^[A-Za-z0-9_-]+$/.test(data.filename)) errors.push('ZIP filename may contain only letters, numbers, _ and -.');
    if (data.song_number !== null && (!(Number.isInteger(data.song_number)) || data.song_number < 1)) errors.push('Song ID must be a positive integer or blank.');
    if (!state.zipFile) errors.push('Select a sound ZIP.');

    activeChains().forEach(function (chain, ci) {
      if (data.mappings[chain].length !== 48) errors.push(chain + ' does not contain 48 pad positions.');
      data.mappings[chain].forEach(function (sample, pad) {
        if (!sample) return;
        var expected = 'sounds/chain' + (ci + 1) + '/' + Audio_Sample_Space.resolveFilename(sample);
        if (state.zipEntries.indexOf(expected) < 0) errors.push(chain + ' pad ' + PAD_LABELS[pad] + ' references missing ' + expected);
      });
      data.linkedAreas[chain].forEach(function (group, gi) {
        if (group.length < 2) warnings.push(chain + ' linked group ' + (gi + 1) + ' has fewer than 2 pads.');
      });
    });

    return { data: data, errors: errors, warnings: warnings };
  }

  function showValidation(result) {
    var el = $('result');
    if (result.errors.length) {
      el.className = 'status bad';
      el.textContent = 'INVALID\n- ' + result.errors.join('\n- ') + (result.warnings.length ? '\n\nWarnings:\n- ' + result.warnings.join('\n- ') : '');
    } else {
      el.className = 'status good';
      el.textContent = 'VALID — ready to export.' + (result.warnings.length ? '\nWarnings:\n- ' + result.warnings.join('\n- ') : '');
    }
  }

  function exportJson() {
    var result = validate();
    showValidation(result);
    if (result.errors.length) return;

    var blob = new Blob([JSON.stringify(result.data, null, 2) + '\n'], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = (result.data.filename || 'song') + '.song.json';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  async function installSong() {
    var result = validate();
    showValidation(result);
    if (result.errors.length) return;

    var button = $('installBtn');
    var previousText = button.textContent;
    button.disabled = true;
    button.textContent = 'Installing...';

    var form = new FormData();
    form.append('manifest', JSON.stringify(result.data));
    form.append('zip', state.zipFile, state.zipFile.name);

    try {
      var response = await fetch('/dev/song_imports', {
        method: 'POST',
        body: form,
        credentials: 'same-origin',
        headers: { 'X-Requested-With': 'XMLHttpRequest' }
      });

      var payload;
      try {
        payload = await response.json();
      } catch (parseError) {
        throw new Error('Server returned a non-JSON response (HTTP ' + response.status + ').');
      }

      if (!response.ok || !payload.ok) {
        var details = [];
        if (payload.error) details.push(payload.error);
        if (payload.errors && payload.errors.length) details = details.concat(payload.errors);
        throw new Error(details.join('\n') || ('Install failed with HTTP ' + response.status + '.'));
      }

      var lines = [
        'INSTALLED SUCCESSFULLY',
        'Name: ' + payload.song.name,
        'Song ID: ' + payload.song.id,
        'Manifest: ' + payload.song.manifest_path,
        'ZIP: ' + payload.song.zip_path,
        '',
        'Reload the Launchpad page and select the new song.'
      ];
      if (payload.warnings && payload.warnings.length) {
        lines.push('', 'Warnings:', '- ' + payload.warnings.join('\n- '));
      }

      $('result').className = 'status good';
      $('result').textContent = lines.join('\n');
    } catch (err) {
      $('result').className = 'status bad';
      $('result').textContent = 'INSTALL FAILED\n' + err.message;
    } finally {
      button.disabled = false;
      button.textContent = previousText;
    }
  }

  function cloneMappings() {
    var mappings = {};
    activeChains().forEach(function (chain) { mappings[chain] = state.mappings[chain].slice(); });
    return mappings;
  }

  function parseLinked(text) {
    if (!text.trim()) return [];
    var groups = [];
    text.split(/\r?\n/).forEach(function (line) {
      line = line.trim();
      if (!line) return;
      var values = line.split(',').map(function (v) { return v.trim(); }).filter(Boolean);
      var group = [];
      values.forEach(function (label) {
        var idx = padIndex(label);
        if (idx < 0) throw new Error('Unknown pad label in linked groups: ' + label);
        if (group.indexOf(idx) < 0) group.push(idx);
      });
      groups.push(group);
    });
    return groups;
  }

  function padIndex(label) {
    var normalized = label.toUpperCase();
    if (normalized === 'RETURN') normalized = 'ENTER';
    if (normalized === 'SPACE') normalized = 'NA';
    for (var i = 0; i < PAD_LABELS.length; i++) {
      if (PAD_LABELS[i].toUpperCase() === normalized) return i;
    }
    var asNum = Number(label);
    if (Number.isInteger(asNum) && asNum >= 0 && asNum < 48) return asNum;
    return -1;
  }

  function sortedNumbers(set) { return Array.from(set).sort(function (a, b) { return a - b; }); }
  function unique(arr) { return arr.filter(function (v, i) { return arr.indexOf(v) === i; }); }
  function naturalSort(a, b) { return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' }); }

  function variableFromFilename(value) {
    var parts = value.split(/[^A-Za-z0-9]+/).filter(Boolean);
    if (!parts.length) return 'songData';
    var first = parts.shift();
    if (/^\d/.test(first)) first = 'song' + first;
    return first + parts.map(function (p) { return p.charAt(0).toUpperCase() + p.slice(1); }).join('') + 'Data';
  }

  // Lists filenames using the ZIP central directory. It does not decompress audio.
  async function listZipEntries(file) {
    var buffer = await file.arrayBuffer();
    var bytes = new Uint8Array(buffer);
    var view = new DataView(buffer);
    var eocd = findSignatureBackwards(bytes, [0x50, 0x4b, 0x05, 0x06], Math.max(0, bytes.length - 65557));
    if (eocd < 0) throw new Error('ZIP end-of-central-directory record not found.');

    var cdSize = view.getUint32(eocd + 12, true);
    var cdOffset = view.getUint32(eocd + 16, true);
    if (cdSize === 0xffffffff || cdOffset === 0xffffffff) throw new Error('ZIP64 is not supported by this MVP.');

    var decoder = new TextDecoder('utf-8');
    var entries = [];
    var pos = cdOffset;
    var end = cdOffset + cdSize;

    while (pos < end) {
      if (view.getUint32(pos, true) !== 0x02014b50) throw new Error('Invalid ZIP central directory at byte ' + pos + '.');
      var nameLen = view.getUint16(pos + 28, true);
      var extraLen = view.getUint16(pos + 30, true);
      var commentLen = view.getUint16(pos + 32, true);
      var nameBytes = bytes.slice(pos + 46, pos + 46 + nameLen);
      entries.push(decoder.decode(nameBytes).replace(/\\/g, '/'));
      pos += 46 + nameLen + extraLen + commentLen;
    }
    return entries;
  }

  function findSignatureBackwards(bytes, sig, min) {
    outer: for (var i = bytes.length - sig.length; i >= min; i--) {
      for (var j = 0; j < sig.length; j++) if (bytes[i + j] !== sig[j]) continue outer;
      return i;
    }
    return -1;
  }

  window.addEventListener('DOMContentLoaded', init);
})();
