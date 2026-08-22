const assert = require('assert');
const ChainControls = require('../../app/assets/javascripts/chainControls.js');

let assertions = 0;

function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}

const arrows = [
  ['ArrowLeft', 0],
  ['ArrowUp', 1],
  ['ArrowDown', 2],
  ['ArrowRight', 3]
];

arrows.forEach(function (entry) {
  equal(ChainControls.resolveShortcut(entry[0], {}), entry[1], entry[0] + ' selects a legacy chain');
  equal(ChainControls.resolveShortcut(entry[0], { ctrlKey: true }), entry[1] + 4, 'Ctrl+' + entry[0] + ' selects an extended chain');
});

[
  { shiftKey: true },
  { altKey: true },
  { metaKey: true },
  { ctrlKey: true, shiftKey: true },
  { ctrlKey: true, altKey: true },
  { ctrlKey: true, metaKey: true }
].forEach(function (modifiers) {
  arrows.forEach(function (entry) {
    equal(ChainControls.resolveShortcut(entry[0], modifiers), -1, entry[0] + ' rejects disallowed modifiers');
  });
});

equal(ChainControls.resolveShortcut('KeyA', {}), -1, 'unknown key is not a chain shortcut');
equal(ChainControls.effectiveChainCount({}), 4, 'missing chain_count falls back to four');
[4, 5, 6, 7, 8].forEach(function (chainCount) {
  equal(ChainControls.effectiveChainCount({ chain_count: chainCount }), chainCount, 'valid chain_count ' + chainCount + ' is preserved');
});
[3, 9, 0, -1, '5', 5.5, null, undefined].forEach(function (chainCount) {
  equal(ChainControls.effectiveChainCount({ chain_count: chainCount }), 4, 'invalid chain_count falls back to four');
});
equal(ChainControls.effectiveChainCount(null), 4, 'missing song data falls back to four');

console.log('keyboard controls tests passed: ' + assertions + ' assertions');
