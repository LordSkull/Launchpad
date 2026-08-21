var Audio_Sample_Space = new function(){
    var supportedExtensions = ['.mp3', '.wav', '.ogg'];
    var mimeTypes = {
        '.mp3': 'audio/mp3',
        '.wav': 'audio/wav',
        '.ogg': 'audio/ogg'
    };

    this.supportedExtensions = supportedExtensions.slice();

    this.extensionFor = function(filename){
        var lower = String(filename || '').toLowerCase();
        for(var i = 0; i < supportedExtensions.length; i++){
            if(lower.endsWith(supportedExtensions[i]))
                return supportedExtensions[i];
        }
        return null;
    };

    this.isSupported = function(filename){
        return this.extensionFor(filename) !== null;
    };

    // Legacy manifests store MP3 sample basenames without an extension.
    this.resolveFilename = function(sample){
        sample = String(sample || '');
        return this.isSupported(sample) ? sample : sample + '.mp3';
    };

    this.mimeTypeFor = function(filename){
        var extension = this.extensionFor(filename);
        return extension ? mimeTypes[extension] : null;
    };
}
