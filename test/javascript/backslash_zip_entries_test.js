const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app/assets/javascripts/loadZip.js', 'utf8');
let loggedError = null;
const context = {
  console: {
    error: function (message) { loggedError = message; },
    log: console.log
  }
};
vm.createContext(context);
vm.runInContext(source, context, { filename: 'loadZip.js' });

let assertions = 0;

function equal(actual, expected, message) {
  assertions += 1;
  assert.strictEqual(actual, expected, message);
}

const findBackslash = context.Zip_Space.findBackslashEntryName;

equal(typeof findBackslash, 'function', 'loadZip exposes focused backslash detection');
equal(findBackslash([
  { filename: 'sounds/chain1/kick.mp3' },
  { filename: 'metadata/item.txt' }
]), null, 'forward-slash entries are accepted');
equal(findBackslash([
  { filename: 'sounds\\chain1\\kick.mp3' }
]), 'sounds\\chain1\\kick.mp3', 'backslash sample path is rejected');
equal(findBackslash([
  { filename: 'sounds/chain1/metadata\\item.txt' }
]), 'sounds/chain1/metadata\\item.txt', 'backslash in any component is rejected');

let extractionCount = 0;
let loadCallbackCalled = false;
let readerClosed = false;
const rendered = {};
const backslashEntries = [
  {
    filename: 'sounds\\chain1\\kick.mp3',
    getData: function () { extractionCount += 1; }
  }
];

context.$ = function (selector) {
  return {
    html: function (value) { rendered[selector] = value; },
    text: function (value) { rendered[selector] = value; }
  };
};
context.zip = {
  BlobReader: function (blob) { this.blob = blob; },
  createReader: function (_blobReader, callback) {
    callback({
      getEntries: function (entriesCallback) { entriesCallback(backslashEntries); },
      close: function (closeCallback) {
        readerClosed = true;
        closeCallback();
      }
    });
  }
};
context.XMLHttpRequest = function () {
  this.open = function () {};
  this.send = function () {
    this.response = {};
    this.onload();
  };
};

context.Zip_Space.loadZip('backslash', function () { loadCallbackCalled = true; });

const expectedError = 'ZIP entry names must use forward slashes (/), not backslashes (\\).';
equal(extractionCount, 0, 'backslash entry is rejected before extraction');
equal(loadCallbackCalled, false, 'backslash ZIP does not complete successfully');
equal(Object.keys(context.Zip_Space.dataArray).length, 0, 'backslash ZIP leaves no sample data');
equal(readerClosed, true, 'backslash ZIP reader is closed');
equal(loggedError, expectedError, 'backslash failure is logged clearly');
equal(rendered['#error_msg'], expectedError, 'backslash failure is shown clearly');

console.log('backslash ZIP entry tests passed: ' + assertions + ' assertions');
