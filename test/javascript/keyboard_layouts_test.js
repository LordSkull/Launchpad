const assert = require('assert');
const KeyboardLayouts = require('../../app/assets/javascripts/keyboardLayouts.js');

let assertions = 0;

function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}

function ok(value, message) {
  assertions += 1;
  assert.ok(value, message);
}

const us = KeyboardLayouts.getLayout('us');
const italian = KeyboardLayouts.getLayout('it');

const expectedUsCodes = [
  'Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5', 'Digit6', 'Digit7', 'Digit8', 'Digit9', 'Digit0', 'Minus', 'Equal',
  'KeyQ', 'KeyW', 'KeyE', 'KeyR', 'KeyT', 'KeyY', 'KeyU', 'KeyI', 'KeyO', 'KeyP', 'BracketLeft', 'BracketRight',
  'KeyA', 'KeyS', 'KeyD', 'KeyF', 'KeyG', 'KeyH', 'KeyJ', 'KeyK', 'KeyL', 'Semicolon', 'Quote', 'Enter',
  'KeyZ', 'KeyX', 'KeyC', 'KeyV', 'KeyB', 'KeyN', 'KeyM', 'Comma', 'Period', 'Slash', 'ShiftRight', 'Backslash'
];
const expectedUsLabels = [
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',
  'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']',
  'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', "'", 'Enter',
  'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', 'Shift', '\\'
];
const expectedItalianCodes = [
  'Digit1', 'Digit2', 'Digit3', 'Digit4', 'Digit5', 'Digit6', 'Digit7', 'Digit8', 'Digit9', 'Digit0', 'Minus', 'Equal',
  'KeyQ', 'KeyW', 'KeyE', 'KeyR', 'KeyT', 'KeyY', 'KeyU', 'KeyI', 'KeyO', 'KeyP', 'BracketLeft', 'BracketRight',
  'KeyA', 'KeyS', 'KeyD', 'KeyF', 'KeyG', 'KeyH', 'KeyJ', 'KeyK', 'KeyL', 'Semicolon', 'Quote', 'Enter',
  'IntlBackslash', 'KeyZ', 'KeyX', 'KeyC', 'KeyV', 'KeyB', 'KeyN', 'KeyM', 'Comma', 'Period', 'Slash', 'ShiftRight'
];
const expectedItalianLabels = [
  '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', "'", 'ì',
  'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'è', '+',
  'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'ò', 'à', 'Enter',
  '<', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '-', 'Shift'
];

equal(us.length, 48, 'US layout has 48 pads');
equal(italian.length, 48, 'Italian layout has 48 pads');
equal(new Set(us.map(function (pad) { return pad.code; })).size, 48, 'US codes are unique');
equal(new Set(italian.map(function (pad) { return pad.code; })).size, 48, 'Italian codes are unique');
equal(JSON.stringify(us.map(function (pad) { return pad.code; })), JSON.stringify(expectedUsCodes), 'US codes match the approved mapping');
equal(JSON.stringify(us.map(function (pad) { return pad.label; })), JSON.stringify(expectedUsLabels), 'US labels match the approved mapping');
equal(JSON.stringify(italian.map(function (pad) { return pad.code; })), JSON.stringify(expectedItalianCodes), 'Italian codes match the approved mapping');
equal(JSON.stringify(italian.map(function (pad) { return pad.label; })), JSON.stringify(expectedItalianLabels), 'Italian labels match the approved mapping');

equal(us[47].code, 'Backslash', 'US pad 47 uses Backslash');
equal(us[47].label, '\\', 'US pad 47 displays backslash');
equal(italian[36].code, 'IntlBackslash', 'Italian pad 36 uses IntlBackslash');
equal(italian[36].label, '<', 'Italian pad 36 displays <');
equal(italian[46].code, 'Slash', 'Italian pad 46 uses Slash');
equal(italian[46].label, '-', 'Italian pad 46 displays -');
equal(italian[47].code, 'ShiftRight', 'Italian pad 47 uses ShiftRight');
equal(italian[47].label, 'Shift', 'Italian pad 47 displays Shift');

['us', 'it'].forEach(function (layoutId) {
  equal(KeyboardLayouts.getPadIndex(layoutId, 'ShiftLeft'), -1, layoutId + ' does not map ShiftLeft');
  ['ArrowLeft', 'ArrowUp', 'ArrowDown', 'ArrowRight'].forEach(function (code) {
    equal(KeyboardLayouts.getPadIndex(layoutId, code), -1, layoutId + ' does not map ' + code);
  });
});

equal(KeyboardLayouts.getPadIndex('us', 'Digit1'), 0, 'US lookup resolves Digit1');
equal(KeyboardLayouts.getPadIndex('us', 'Backslash'), 47, 'US lookup resolves Backslash');
equal(KeyboardLayouts.getPadIndex('it', 'IntlBackslash'), 36, 'Italian lookup resolves IntlBackslash');
equal(KeyboardLayouts.getPadIndex('it', 'Slash'), 46, 'Italian lookup resolves Slash');
equal(KeyboardLayouts.getLayoutId('unknown'), 'us', 'unknown layout falls back to US');

equal(KeyboardLayouts.loadLayout({ getItem: function () { return 'us'; } }), 'us', 'stored us loads as us');
equal(KeyboardLayouts.loadLayout({ getItem: function () { return 'it'; } }), 'it', 'stored it loads as it');
equal(KeyboardLayouts.loadLayout({ getItem: function () { return 'invalid'; } }), 'us', 'invalid stored layout falls back to US');
equal(KeyboardLayouts.loadLayout({ getItem: function () { return null; } }), 'us', 'missing stored layout falls back to US');
equal(KeyboardLayouts.loadLayout({ getItem: function () { throw new Error('unavailable'); } }), 'us', 'unavailable storage falls back to US');

let storedKey;
let storedValue;
equal(KeyboardLayouts.saveLayout('it', {
  setItem: function (key, value) {
    storedKey = key;
    storedValue = value;
  }
}), 'it', 'saveLayout returns the selected layout');
equal(storedKey, 'launchpad.keyboardLayout', 'layout uses the approved storage key');
equal(storedValue, 'it', 'layout stores the selected value');
ok(KeyboardLayouts.getLayout('unknown') === us, 'unknown descriptor lookup returns US');

console.log('keyboard layout tests passed: ' + assertions + ' assertions');
