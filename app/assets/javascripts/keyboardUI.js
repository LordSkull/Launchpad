var Keyboard_UI_Space = new function(){
    
    this.initKeyboardUI = function(){
        return new KeyboardUI();
    }
    
    var KeyboardUI = function(){
        this.currentLayoutId = Keyboard_Layout_Space.loadLayout();
        this.activePadByCode = {};
    }
    
    KeyboardUI.prototype.initUI = function(){
        // info, links, and songs buttons
        $(".click_button").css("display", "inline-block");
        
        $(".click_button").click(function(){
            var thisObj = this;
            if($("#"+$(thisObj).attr("toggle_id")).css("display") == "none"){
                $(".toggle_container").css("display", "none");
                
                $("#"+$(thisObj).attr("toggle_id")).toggle(300, function(){
                    if($("#"+$(thisObj).attr("toggle_id")).css("display") == "block"){
                        $(thisObj).css("background-color","lightgray");
                        $("html, body").animate({ scrollTop: $(document).height()-$(window).height() }, 300);
                    }
                });
            }
            else{
                $("#"+$(thisObj).attr("toggle_id")).toggle(300, function(){
                    if($("#"+$(thisObj).attr("toggle_id")).css("display") == "block"){
                        $(thisObj).css("background-color","lightgray");
                        $("html, body").animate({ scrollTop: $(document).height()-$(window).height() }, 300);
                    }
                });
            }
            $(".click_button").css("background-color","white");
        });
        
        $("#left_ad, #right_ad").css({"bottom":"10px","top":"auto"});
    }
    
    // setup touchscreen, kind of works
    KeyboardUI.prototype.touchScreenSetup = function(keyboard){
        $(".button").bind("touchstart", function(event){
            if (Howler.ctx.state != "running") {
                Howler.ctx.resume();
            }
           var num = parseInt($(this).attr("buttonnum"));
           keyboard.pressPad(num);
           event.preventDefault();
           return false;
        });
        
        $(".button").bind("touchend", function(event){
           var num = parseInt($(this).attr("buttonnum"));
           keyboard.releasePad(num);
           event.preventDefault();
           return false;
        });
        
        $(".button").bind("touchcancel", function(event){
           var num = parseInt($(this).attr("buttonnum"));
           keyboard.releasePad(num);
           event.preventDefault();
           return false;
        });
    }
    
    // creates elements for keyboard and appends them to the document
    KeyboardUI.prototype.loadKeyboard = function(keyboard, currentSongData, currentSoundPack){
        for(var i = 0; i < 4; i++){
            // create new row
            $(".buttons").append('<div class="button-row"></div>');
            // create 12 buttons per row
            for(var j = 0; j < 12; j++){
                var press = false;
                if(currentSongData["holdToPlay"]["chain"+(currentSoundPack+1)].indexOf((i*12+j)) != -1)
                    press = true;
                var str = Keyboard_Layout_Space.getLabel(this.currentLayoutId, i*12+j);
                var button = $("<div></div>")
                    .addClass("button button-"+(i*12+j))
                    .toggleClass("button-label-long", str.length > 2)
                    .attr("pressure", press)
                    .attr("released", "true")
                    .attr("buttonnum", i*12+j)
                    .text(str);
                $(".button-row:last").append(button);
                // holdToPlay coloring, turned off for now
                //$('.button-'+(i*12+j)+'').css("background-color", $('.button-'+(i*12+j)+'').attr("pressure") == "true" ? "lightgray" : "white");
            }
        }
        
        $(".soundPack").html("Sound Pack: "+(currentSoundPack+1));
        $("#keyboard_layout").val(this.currentLayoutId);
        
        if(!loaded){
            $("#sound_pack_buttons").append('<div class="sound_pack_button sound_pack_button_2">^</div>');
            $("#sound_pack_buttons").append('<div class="sound_pack_button sound_pack_button_1"><</div>');
            $("#sound_pack_buttons").append('<div class="sound_pack_button sound_pack_button_3">v</div>');
            $("#sound_pack_buttons").append('<div class="sound_pack_button sound_pack_button_4">></div>');
            $(".sound_pack_button_"+(currentSoundPack+1)).css("background-color","rgb(255,160,0)");
            
            this.touchScreenSetup(keyboard);
            this.layoutSelectionSetup(keyboard);
            
            this.keyPressSetup(keyboard);
            
            keyboard.initUI();
            
            this.initUI();
            
            loaded = true;
        }
    }

    KeyboardUI.prototype.isInteractiveTarget = function(target){
        while(target && target != document){
            var tagName = target.tagName ? target.tagName.toLowerCase() : "";
            if(tagName == "input" || tagName == "textarea" || tagName == "select" || tagName == "button" || tagName == "a" || target.isContentEditable)
                return true;
            target = target.parentElement;
        }
        return false;
    }

    KeyboardUI.prototype.releaseActiveKeyboardPads = function(keyboard){
        for(var code in this.activePadByCode){
            if(this.activePadByCode.hasOwnProperty(code))
                keyboard.releasePad(this.activePadByCode[code]);
        }
        this.activePadByCode = {};
    }

    KeyboardUI.prototype.updateKeyboardLabels = function(){
        for(var i = 0; i < 48; i++){
            var label = Keyboard_Layout_Space.getLabel(this.currentLayoutId, i);
            $(".button-"+i)
                .toggleClass("button-label-long", label.length > 2)
                .text(label);
        }
    }

    KeyboardUI.prototype.layoutSelectionSetup = function(keyboard){
        var thisObj = this;
        $("#keyboard_layout").val(this.currentLayoutId).change(function(){
            thisObj.releaseActiveKeyboardPads(keyboard);
            thisObj.currentLayoutId = Keyboard_Layout_Space.saveLayout($(this).val());
            $(this).val(thisObj.currentLayoutId);
            thisObj.updateKeyboardLabels();
        });
    }

    KeyboardUI.prototype.getEventCode = function(event){
        if(event.code)
            return event.code;
        if(event.originalEvent)
            return event.originalEvent.code;
        return undefined;
    }
    
    // setup keypress on document
    KeyboardUI.prototype.keyPressSetup = function(keyboard){
        var thisObj = this;
        $(document).keydown(function(e){
            if(thisObj.isInteractiveTarget(e.target))
                return;
            if (Howler.ctx.state != "running") {
                Howler.ctx.resume();
            }

            var code = thisObj.getEventCode(e);
            var noModifiers = !(e.ctrlKey || e.metaKey || e.altKey || e.shiftKey);
            var isChainCode = ["ArrowLeft", "ArrowUp", "ArrowDown", "ArrowRight"].indexOf(code) != -1;
            if(noModifiers && isChainCode){
                thisObj.releaseActiveKeyboardPads(keyboard);
                keyboard.switchSoundPackCheck(code);
                e.preventDefault();
                return;
            }

            if(e.ctrlKey || e.metaKey || e.altKey)
                return;

            var padIndex = Keyboard_Layout_Space.getPadIndex(thisObj.currentLayoutId, code);
            if(padIndex != -1){
                if(!e.repeat && !thisObj.activePadByCode.hasOwnProperty(code)){
                    thisObj.activePadByCode[code] = padIndex;
                    keyboard.pressPad(padIndex);
                }
                e.preventDefault();
            }
        });
        
        $(document).keyup(function(e){
            var code = thisObj.getEventCode(e);
            if(thisObj.activePadByCode.hasOwnProperty(code)){
                keyboard.releasePad(thisObj.activePadByCode[code]);
                delete thisObj.activePadByCode[code];
                e.preventDefault();
            }
        });
    }
    
    var loaded = false;
}
