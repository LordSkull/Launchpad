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

const findDuplicate = context.Zip_Space.findDuplicateEntryName;

equal(typeof findDuplicate, 'function', 'loadZip exposes focused duplicate detection');
equal(findDuplicate([
  { filename: 'sounds/chain1/kick.mp3' },
  { filename: 'sounds/chain1/kick.mp3' }
]), 'sounds/chain1/kick.mp3', 'exact duplicate is rejected');
equal(findDuplicate([
  { filename: 'sounds/chain1/kick.mp3' },
  { filename: 'sounds/chain1/KICK.MP3' }
]), null, 'case-distinct names remain distinct');
equal(findDuplicate([
  { filename: 'sounds/chain1/kick.mp3' },
  { filename: 'sounds/chain1/snare.mp3' }
]), null, 'unique names are accepted');

let extractionCount = 0;
let loadCallbackCalled = false;
let readerClosed = false;
const rendered = {};
const duplicateEntries = [
  {
    filename: 'sounds/chain1/kick.mp3',
    getData: function () { extractionCount += 1; }
  },
  {
    filename: 'sounds/chain1/kick.mp3',
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
      getEntries: function (entriesCallback) { entriesCallback(duplicateEntries); },
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

context.Zip_Space.loadZip('duplicate', function () { loadCallbackCalled = true; });

equal(extractionCount, 0, 'duplicate entries are rejected before extraction');
equal(loadCallbackCalled, false, 'duplicate ZIP does not complete successfully');
equal(Object.keys(context.Zip_Space.dataArray).length, 0, 'duplicate ZIP leaves no sample data');
equal(readerClosed, true, 'duplicate ZIP reader is closed');
equal(loggedError, 'Duplicate ZIP entry: sounds/chain1/kick.mp3', 'duplicate failure is logged clearly');
equal(rendered['#error_msg'], 'Duplicate ZIP entry: sounds/chain1/kick.mp3', 'duplicate failure is shown clearly');

console.log('duplicate ZIP entry tests passed: ' + assertions + ' assertions');
