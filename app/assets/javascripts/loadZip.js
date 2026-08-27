var Zip_Space = new function(){
  // map chain keys to sound base64 uris
  this.dataArray = {};
  
  this.initialize = function() {
    // point to the z-worker and inflate scripts
    zip.workerScripts = {
      inflater: ['zip/src/z-worker.js', 'zip/src/inflate.js']
    }; 
  }

  this.findDuplicateEntryName = function(entries) {
    var seen = Object.create(null);
    for(var i = 0; i < entries.length; i++) {
      var filename = entries[i].filename;
      if(Object.prototype.hasOwnProperty.call(seen, filename))
        return filename;
      seen[filename] = true;
    }
    return null;
  }

  this.findBackslashEntryName = function(entries) {
    for(var i = 0; i < entries.length; i++) {
      if(entries[i].filename.indexOf('\\') !== -1)
        return entries[i].filename;
    }
    return null;
  }

  function rejectZip(reader, message) {
    Zip_Space.dataArray = {};
    console.error(message);
    $(".soundPack").html("ZIP load failed.");
    $("#error_msg").text(message);
    reader.close(function() {});
  }
  
  // recursively iterate over the entries
  interateEntries = function(entries, i, reader, callback){
    if(i < entries.length){
      // skip this entry if it is a directory
      if(entries[i].directory)
        interateEntries(entries, i+1, reader, callback);
      // only accept supported audio sample files
      else if(Audio_Sample_Space.isSupported(entries[i].filename)) {
        entries[i].getData(new zip.Data64URIWriter(Audio_Sample_Space.mimeTypeFor(entries[i].filename)), function(data) {
          Zip_Space.dataArray[entries[i].filename] = data;
          interateEntries(entries, i+1, reader, callback);
        });
      // skip
      } else {
        interateEntries(entries, i+1, reader, callback);
      }
    } else {  // at the end, so close reader
      reader.close(function() {
        callback();
      });
    }
  }
  
  this.loadZip = function(name, callback){
    // get request for zip file
    this.dataArray = {};
    var xhr = new XMLHttpRequest()
    xhr.open("GET", 'zip/sounds/'+name+'.zip')
    xhr.responseType = "blob"
    xhr.onload = function(){
        // console.log(xhr.response)
        // create the zip reader for the zip file blob
        zip.createReader(new zip.BlobReader(xhr.response), function(reader) {
          $(".soundPack").html("Extracting Sounds...");
          // get all entries from the zip
          reader.getEntries(function(entries) {
            var backslashEntry = Zip_Space.findBackslashEntryName(entries);
            if(backslashEntry !== null) {
              rejectZip(reader, "ZIP entry names must use forward slashes (/), not backslashes (\\).");
              return;
            }
            var duplicateEntry = Zip_Space.findDuplicateEntryName(entries);
            if(duplicateEntry !== null) {
              rejectZip(reader, "Duplicate ZIP entry: " + duplicateEntry);
              return;
            }
            interateEntries(entries, 0, reader, callback);
          });
        }, function(error) {
          console.log(error);
          $("#error_msg").html("There was a critical error. Try clearing your browser's cache or check back later.");
        });
    }
    xhr.send()
    $(".soundPack").html("Loading main sound file...");
  }
}
