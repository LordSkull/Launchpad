var Keyboard_Layout_Space = new function(){
    var storageKey = "launchpad.keyboardLayout";
    var defaultLayoutId = "us";

    var layouts = {
        us: [
            {code:"Digit1", label:"1"}, {code:"Digit2", label:"2"}, {code:"Digit3", label:"3"}, {code:"Digit4", label:"4"},
            {code:"Digit5", label:"5"}, {code:"Digit6", label:"6"}, {code:"Digit7", label:"7"}, {code:"Digit8", label:"8"},
            {code:"Digit9", label:"9"}, {code:"Digit0", label:"0"}, {code:"Minus", label:"-"}, {code:"Equal", label:"="},
            {code:"KeyQ", label:"Q"}, {code:"KeyW", label:"W"}, {code:"KeyE", label:"E"}, {code:"KeyR", label:"R"},
            {code:"KeyT", label:"T"}, {code:"KeyY", label:"Y"}, {code:"KeyU", label:"U"}, {code:"KeyI", label:"I"},
            {code:"KeyO", label:"O"}, {code:"KeyP", label:"P"}, {code:"BracketLeft", label:"["}, {code:"BracketRight", label:"]"},
            {code:"KeyA", label:"A"}, {code:"KeyS", label:"S"}, {code:"KeyD", label:"D"}, {code:"KeyF", label:"F"},
            {code:"KeyG", label:"G"}, {code:"KeyH", label:"H"}, {code:"KeyJ", label:"J"}, {code:"KeyK", label:"K"},
            {code:"KeyL", label:"L"}, {code:"Semicolon", label:";"}, {code:"Quote", label:"'"}, {code:"Enter", label:"Enter"},
            {code:"KeyZ", label:"Z"}, {code:"KeyX", label:"X"}, {code:"KeyC", label:"C"}, {code:"KeyV", label:"V"},
            {code:"KeyB", label:"B"}, {code:"KeyN", label:"N"}, {code:"KeyM", label:"M"}, {code:"Comma", label:","},
            {code:"Period", label:"."}, {code:"Slash", label:"/"}, {code:"ShiftRight", label:"Shift"}, {code:"Backslash", label:"\\"}
        ],
        it: [
            {code:"Digit1", label:"1"}, {code:"Digit2", label:"2"}, {code:"Digit3", label:"3"}, {code:"Digit4", label:"4"},
            {code:"Digit5", label:"5"}, {code:"Digit6", label:"6"}, {code:"Digit7", label:"7"}, {code:"Digit8", label:"8"},
            {code:"Digit9", label:"9"}, {code:"Digit0", label:"0"}, {code:"Minus", label:"'"}, {code:"Equal", label:"ì"},
            {code:"KeyQ", label:"Q"}, {code:"KeyW", label:"W"}, {code:"KeyE", label:"E"}, {code:"KeyR", label:"R"},
            {code:"KeyT", label:"T"}, {code:"KeyY", label:"Y"}, {code:"KeyU", label:"U"}, {code:"KeyI", label:"I"},
            {code:"KeyO", label:"O"}, {code:"KeyP", label:"P"}, {code:"BracketLeft", label:"è"}, {code:"BracketRight", label:"+"},
            {code:"KeyA", label:"A"}, {code:"KeyS", label:"S"}, {code:"KeyD", label:"D"}, {code:"KeyF", label:"F"},
            {code:"KeyG", label:"G"}, {code:"KeyH", label:"H"}, {code:"KeyJ", label:"J"}, {code:"KeyK", label:"K"},
            {code:"KeyL", label:"L"}, {code:"Semicolon", label:"ò"}, {code:"Quote", label:"à"}, {code:"Enter", label:"Enter"},
            {code:"IntlBackslash", label:"<"}, {code:"KeyZ", label:"Z"}, {code:"KeyX", label:"X"}, {code:"KeyC", label:"C"},
            {code:"KeyV", label:"V"}, {code:"KeyB", label:"B"}, {code:"KeyN", label:"N"}, {code:"KeyM", label:"M"},
            {code:"Comma", label:","}, {code:"Period", label:"."}, {code:"Slash", label:"-"}, {code:"ShiftRight", label:"Shift"}
        ]
    };

    this.getLayoutId = function(layoutId){
        return layouts.hasOwnProperty(layoutId) ? layoutId : defaultLayoutId;
    };

    this.getLayout = function(layoutId){
        return layouts[this.getLayoutId(layoutId)];
    };

    this.getPadIndex = function(layoutId, code){
        var layout = this.getLayout(layoutId);
        for(var i = 0; i < layout.length; i++){
            if(layout[i].code == code)
                return i;
        }
        return -1;
    };

    this.getLabel = function(layoutId, padIndex){
        var pad = this.getLayout(layoutId)[padIndex];
        return pad ? pad.label : "";
    };

    this.loadLayout = function(storage){
        try{
            if(typeof storage == "undefined" && typeof window != "undefined")
                storage = window.localStorage;
            if(!storage)
                return defaultLayoutId;
            return this.getLayoutId(storage.getItem(storageKey));
        }
        catch(error){
            return defaultLayoutId;
        }
    };

    this.saveLayout = function(layoutId, storage){
        var selectedLayoutId = this.getLayoutId(layoutId);
        try{
            if(typeof storage == "undefined" && typeof window != "undefined")
                storage = window.localStorage;
            if(storage)
                storage.setItem(storageKey, selectedLayoutId);
        }
        catch(error){
            // The in-memory selection remains usable when browser storage is unavailable.
        }
        return selectedLayoutId;
    };
}

if(typeof module != "undefined" && module.exports)
    module.exports = Keyboard_Layout_Space;
