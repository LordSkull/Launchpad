var Keyboard_Space = new function(){

    this.initKeyboard = function(){
        return new Keyboard();
    }
    
    var Keyboard = function(){
        currentChainCount = Chain_Control_Space.effectiveChainCount(currentSongData);
        allocateCurrentSounds();
            
        var this_obj = this;
        Zip_Space.loadZip(currentSongData["filename"], function() {
            loadCurrentSongSounds(this_obj);
            
            this_obj.keyboardUI = Keyboard_UI_Space.initKeyboardUI();
            
            console.log("New keyboard created");  
        })
    }
    
    Keyboard.prototype.getCurrentSounds = function(){
        return currentSounds;
    }

    Keyboard.prototype.getCurrentChainCount = function(){
        return currentChainCount;
    }

    Keyboard.prototype.isSoundPackAvailable = function(sp){
        return Number.isInteger(sp) && sp >= 0 && sp < currentChainCount;
    }
    
    // loads sounds from srcArray for given chain into soundArr
    Keyboard.prototype.loadSounds = function(srcArr, soundArr, chain){
        for(var i = 0; i < srcArr.length; i++)
            soundArr.push(null);
    
        for(var i = 0; i < srcArr.length; i++){
            if(srcArr[i] == "")
                this.checkLoaded();
            else
                this.requestSound(i, srcArr, soundArr, chain);
        }
    }
    
    // makes request for sounds
    // if offline version, gets from local files
    // if online version, gets from public folder
    Keyboard.prototype.requestSound = function(i, srcArr, soundArr, chain){
        var thisObj = this;
        var sampleFilename = Audio_Sample_Space.resolveFilename(srcArr[i]);
        var samplePath = 'sounds/chain'+chain+'/'+sampleFilename;
        soundArr[i] = new Howl({
            // for online version
            urls: [Zip_Space.dataArray[samplePath]],
            // old
            // urls: [currentSongData["soundUrls"]["chain"+chain][srcArr[i]].replace("www.dropbox.com","dl.dropboxusercontent.com").replace("?dl=0","")],
            // for offline version
            // urls: ["audio/chain"+chain+"/"+sampleFilename],
            onload: function(){
                thisObj.checkLoaded();
            },
            onloaderror: function(id, error){
                console.log('error: '+id)
                console.log(error);
                console.log(samplePath);
                $("#error_msg").html("There was an error. Please try clearing your browser's cache and reload the page.");
            }
        });
    }
    
    // checks if all of the sounds have loaded
    // if they have, load the keyboard
    Keyboard.prototype.checkLoaded = function(){
        numSoundsLoaded++;
        var loadingTarget = 48*currentChainCount;
        $(".soundPack").html("Loading sounds ("+numSoundsLoaded+"/"+loadingTarget+")");
        if(numSoundsLoaded == loadingTarget){
            loadingSongs = false;
            this.keyboardUI.loadKeyboard(this, currentSongData, currentSoundPack, currentChainCount);
        }
    }
    
    Keyboard.prototype.switchSoundPackCheck = function(code, modifiers){
        var target = Chain_Control_Space.resolveShortcut(code, modifiers);
        return target != -1 && this.switchSoundPack(target);
    }
    
    // switch sound pack and update pressures
    Keyboard.prototype.switchSoundPack = function(sp){
        if(!this.isSoundPackAvailable(sp))
            return false;

        // release all keys
        for(var i = 0; i < 4; i++)
            for(var j = 0; j < 12; j++)
                if($(".button-"+(i*12+j)+"").attr("released") == "false")
                    this.releasePad(i*12+j);
        
        // set the new soundpack
        currentSoundPack = sp;
        
        $(".soundPack").html("Chain: "+(currentSoundPack+1));
        if(this.keyboardUI)
            this.keyboardUI.refreshChainControls(this, currentChainCount, currentSoundPack);
        // set pressures for buttons in new sound pack
        for(var i = 0; i < 4; i++){
            for(var j = 0; j < 12; j++){
                var press = false;
                var holdToPlay = currentSongData["holdToPlay"]["chain"+(currentSoundPack+1)] || [];
                if(holdToPlay.indexOf((i*12+j)) != -1)
                    press = true;
                $('.button-'+(i*12+j)+'').attr("pressure", ""+press+"");
                // holdToPlay coloring, turned off for now
                //$('.button-'+(i*12+j)+'').css("background-color", $('.button-'+(i*12+j)+'').attr("pressure") == "true" ? "lightgray" : "white");
            }
        }
        return true;
    }
    
    // key released
    // stop playing sound if holdToPlay
    Keyboard.prototype.releasePad = function(padIndex){
        if(currentSounds[currentSoundPack][padIndex] != null){
            this.midiKeyUp(padIndex);
        }
    }
    
    Keyboard.prototype.midiKeyUp = function(padIndex){
        if(currentSounds[currentSoundPack][padIndex] != null){
            if($(".button-"+(padIndex)+"").attr("pressure") == "true")
                currentSounds[currentSoundPack][padIndex].stop();
            $(".button-"+(padIndex)+"").attr("released","true");
            // holdToPlay coloring, turned off for now

            // Removes Style Attribute to clean up HTML
            $(".button-"+(padIndex)+"").removeAttr("style");

            if($(".button-"+(padIndex)+"").hasClass("pressed") == true)
	                $(".button-"+(padIndex)+"").removeClass("pressed");

            //$(".button-"+(padIndex)+"").css("background-color", $(".button-"+(padIndex)+"").attr("pressure") == "true" ? "lightgray" : "white");
        }
    }
    
    // play the key by finding the mapping,
    // stopping all sounds in key's linkedArea
    // and then playing sound
    Keyboard.prototype.pressPad = function(padIndex){
        if(currentSounds[currentSoundPack][padIndex] != null){
            this.midiKeyDown(padIndex);
        }
    }
    
    Keyboard.prototype.midiKeyDown = function(padIndex){
        if(currentSounds[currentSoundPack][padIndex] != null){
            currentSounds[currentSoundPack][padIndex].stop();
            currentSounds[currentSoundPack][padIndex].play();
                
            // go through all linked Areas in current chain
            var linkedAreas = currentSongData["linkedAreas"]["chain"+(currentSoundPack+1)] || [];
            linkedAreas.forEach(function(el, ind, arr){
                // for ever linked area array
                for(var j = 0; j < el.length; j++){
                    // if pad index is in linked area array
                    if(padIndex == el[j]){
                        // stop all other sounds in linked area array
                        for(var k = 0; k < el.length; k++){
                            if(k != j)
                                currentSounds[currentSoundPack][el[k]].stop();
                        }
                        break;
                    }
                }
            });
                
            // set button color and attribute
            $(".button-"+(padIndex)+"").addClass("pressed");
            $(".button-"+(padIndex)+"").attr("released","false");
            //$(".button-"+(padIndex)+"").css("background-color","rgb(255,160,0)");
        }
    }
    
    // shows and formats all of the UI elements
    Keyboard.prototype.initUI = function(){
        for(var s in songDatas){
            var songSelection = $("<div></div>")
                .addClass("song_selection")
                .attr("songInd", s)
                .text(songDatas[s].song_name);
            $("#songs_container").append(songSelection);
        }
        $("[songInd='"+currentSongInd+"']").css("background-color","rgb(220,220,220)");
        
        var mainObj = this; 
        
        $(".song_selection").click(function() {
            var tempS = parseInt($(this).attr("songInd"));
            if(tempS != currentSongInd && !loadingSongs){
                mainObj.keyboardUI.releaseActiveKeyboardPads(mainObj);
                loadingSongs = true;
                currentSongInd = tempS
                currentSongData = songDatas[currentSongInd];
                currentSoundPack = 0;
                currentChainCount = Chain_Control_Space.effectiveChainCount(currentSongData);
                mainObj.keyboardUI.refreshChainControls(mainObj, currentChainCount, currentSoundPack);
                $(".song_selection").css("background-color","white");
                $("[songInd='"+currentSongInd+"']").css("background-color","rgb(220,220,220)");
                
                $(".button-row").remove();
                
                for(var i = 0; i < currentSounds.length; i++){
                    for(var k = 0; k < currentSounds[i].length; k++){
                        if(currentSounds[i][k] != null)
                            currentSounds[i][k].unload();
                    }
                }
                allocateCurrentSounds();
                numSoundsLoaded = 0;
                Zip_Space.loadZip(currentSongData["filename"], function() {
                    loadCurrentSongSounds(mainObj);
                })
                
            }
        });
    }
    
    function allocateCurrentSounds(){
        currentSounds = [];
        for(var i = 0; i < currentChainCount; i++)
            currentSounds.push([]);
    }

    function loadCurrentSongSounds(keyboard){
        for(var chainNumber = 1; chainNumber <= currentChainCount; chainNumber++)
            keyboard.loadSounds(currentSongData["mappings"]["chain"+chainNumber], currentSounds[chainNumber-1], chainNumber);
    }

    // current soundpack (zero-based)
    var currentSoundPack = 0;
    // number of sounds loaded
    var numSoundsLoaded = 0;
    // howl objects for current song
    var currentSounds = [];
    // reference to current song data
    var songDatas = [equinoxData, animalsData, electroData, ghetData, kyotoData, aeroData].concat(window.userSongDatas || []);
    var currentSongInd = 0;
    var currentSongData = equinoxData;
    // number of chains in the current song
    var currentChainCount = Chain_Control_Space.effectiveChainCount(currentSongData);
    
    var loadingSongs = true;

}
