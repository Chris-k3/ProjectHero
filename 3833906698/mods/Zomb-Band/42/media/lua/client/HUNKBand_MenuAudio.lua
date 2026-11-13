-- User-supplied UI cues use the UI emitter; never add AI world sound or network commands.
return function(UI,C,B)
    local A={voices={},last={},index={},fired={}}
    local pools={move={'menumove1_t','menumove2_u','menumove3_v','menumove4_w'},
        select={'menusel1_g','menusel2_h','menusel3_i','menusel4_j','menusel5_k','menusel7_l','menusel8_m','menusel9_n','menusel10_o','menusel11_p','menusel12_q','menusel13_r','menusel14_s'},
        back={'menuback1_x','menuback2_y','menuback3_z'},open={'swoosh'}}
    local function manager() return getSoundManager and getSoundManager() end
    local function stop(voice)
        local sound=manager();if sound and sound.stopUISound then pcall(function() sound:stopUISound(voice.handle) end) end
    end
    function A.stop(group)
        for i=#A.voices,1,-1 do local voice=A.voices[i]
            if not group or voice.group==group then stop(voice);table.remove(A.voices,i) end
        end
    end
    function A.play(kind,group,exact)
        local sound=manager();if not sound or not sound.playUISound then return false end
        local now=B.now();local gap=kind=='move' and 85 or 65
        if not exact and now-(A.last[kind] or -10000)<gap then return false end
        A.last[kind]=now
        local name=exact
        if not name then local pool=pools[kind];if not pool then return false end
            A.index[kind]=(A.index[kind] or 0)%#pool+1;name=pool[A.index[kind]]
        end
        name='ZB_UI_'..name
        if GameSounds and not GameSounds.isKnownSound(name) then
            if A.missing~=name then print('[Zomb-Band MENU] missing '..name..'; restart after installing the sound files');A.missing=name end
            return false
        end
        group=group or 'menu'
        if group=='menu' then A.stop('menu') end -- rapid scrolling never stacks long navigation clips
        local ok,handle=pcall(function() return sound:playUISound(name) end)
        if ok and handle and handle~=0 then A.voices[#A.voices+1]={handle=handle,group=group,untilAt=now+8000};return true end
        return false
    end
    function C.menuCue(kind) return A.play(kind) end
    -- Only authoritative fail-out packets invoke this; predicted misses never do.
    function C.playFailureCue(session)
        if not session then return false end
        local token=tostring(session.id)..':'..session.round
        if A.failureToken==token then return false end
        A.failureToken=token;A.stop('startup');A.stop('menu');A.stop('failure')
        return A.play('failure','failure','overdrive_end')
    end
    local resetRound=C.resetRound
    if resetRound then function C.resetRound(...) A.stop('failure');return resetRound(...) end end
    function C.stopMenuAudio() A.stop();A.round=nil;A.fired={};A.failureToken=nil end
    function C.menuAudioUpdate()
        local now=B.now();local sound=manager()
        for i=#A.voices,1,-1 do local v=A.voices[i];local done=now>=v.untilAt
            if sound and sound.isPlayingUISound then local ok,playing=pcall(function() return sound:isPlayingUISound(v.handle) end);if ok and not playing then done=true end end
            if done then stop(v);table.remove(A.voices,i) end
        end
        local s=C.getSession();local me=C.me(s)
        if not C.window or not s or not me or (s.phase~='countdown' and s.phase~='playing') then A.stop('startup');A.round=nil;return end
        if isClient() and #C.samples<3 then return end
        local token=s.id..':'..s.round..':'..s.startsAt
        if A.round~=token then A.stop('startup');A.round=token;A.fired={} end
        local at=C.elapsed(s)
        if at>=0 then A.stop('startup');return end
        local stringed=me.kind=='guitar' or me.kind=='acoustic' or me.kind=='bass' or me.kind=='banjo'
        local intro=stringed and (s.round%2==1 and 'guitarstartup_a' or 'guitarstart_ga') or 'startup2_fa'
        local cd=-(B.countdownMs or 3000)
        local stages={{at=cd,key='intro',name=intro},{at=math.floor(cd*0.84),key='crowd',name=s.round%2==1 and 'ampcrowdstartup_da' or 'cheers_startup'},
            {at=-1050,key='transition',name='swoosh'}}
        for _,stage in ipairs(stages) do if not A.fired[stage.key] and at>=stage.at then
            A.fired[stage.key]=true
            -- A late join/update skips stale cues; it never changes the shared music clock.
            if at-stage.at<=350 then A.play(stage.key,'startup',stage.name) end
        end end
    end
    local create=UI.createChildren
    function UI:createChildren()
        create(self)
        for _,child in pairs(self.children or {}) do if child.onclick or child.callback then
            child.sounds=child.sounds or {};child.sounds.activate='ZB_UI_Silent'
        end end
    end
    for _,name in ipairs({'play','form','join','replay','chooseDifficulty','favoriteSong','previewSong','cycleSort','nextInstrument','clearSearch','checkCamera','lessOffset','moreOffset'}) do
        local fn=UI[name]
        if fn then UI[name]=function(self,...) A.play('select');return fn(self,...) end end
    end
    local exit=UI.exitBand
    function UI:exitBand(...) A.stop('startup');A.stop('failure');A.play('back');return exit(self,...) end
    local open=C.open
    function C.open(...) local hadWindow=C.window;local result=open(...);if C.window and not hadWindow then A.play('open') end;return result end
    C.menuAudio=A
end
