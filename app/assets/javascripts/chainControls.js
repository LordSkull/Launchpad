var Chain_Control_Space = new function(){
    var minimumChainCount = 4;
    var maximumChainCount = 8;
    var legacyChainCount = 4;
    var arrowIndexByCode = {
        ArrowLeft: 0,
        ArrowUp: 1,
        ArrowDown: 2,
        ArrowRight: 3
    };

    this.minimumChainCount = minimumChainCount;
    this.maximumChainCount = maximumChainCount;
    this.legacyChainCount = legacyChainCount;

    this.effectiveChainCount = function(songData){
        if(!songData)
            return legacyChainCount;
        var count = songData.chain_count;
        return Number.isInteger(count) && count >= minimumChainCount && count <= maximumChainCount ? count : legacyChainCount;
    };

    this.resolveShortcut = function(code, modifiers){
        modifiers = modifiers || {};
        if(modifiers.shiftKey || modifiers.altKey || modifiers.metaKey)
            return -1;
        if(!arrowIndexByCode.hasOwnProperty(code))
            return -1;
        return arrowIndexByCode[code] + (modifiers.ctrlKey ? legacyChainCount : 0);
    };
}

if(typeof module != "undefined" && module.exports)
    module.exports = Chain_Control_Space;
