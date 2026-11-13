require 'HUNKBand_Shared'
require 'ISUI/ISPanel'
require 'ISUI/ISButton'
require 'ISUI/ISComboBox'
require 'ISUI/ISContextMenu'
require 'ISUI/ISToolTip'
require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
require 'HUNKBand_Animation'
require 'HUNKBand_Camera'
require 'HUNKBand_Library'
HUNKBandClient={}
local C,B=HUNKBandClient,HUNKBand
C.sessions={};C.active=nil;C.window=nil;C.itemType=nil
C.song=1;C.difficulty=2;C.status='Choose a song and your difficulty.'
C.clockOffset=0;C.samples={};C.pings={};C.nonce=0;C.lastPing=-10000;C.lastDiscover=-10000
C.state=B.newPerformance();C.base=B.newPerformance();C.pending={};C.seq=0
C.roundKey=nil;C.lockOffset=nil;C.lastJudgement='';C.lastJudgementAt=0
C.audio={};C.effects={};C.schedules={};C.noteSounds={};C.autoWalked={};C.calibration=0
C.preparedAudio={};C.audioRetryAt={};C.audioLogged={};C.audioError=nil;C.hudCentered=true
local function audioFailure(name,reason)
    local message='Audio '..tostring(name)..': '..tostring(reason)
    C.audioError=message;C.status=message
    if not C.audioLogged[message] then print('[Zomb-Band AUDIO] '..message);C.audioLogged[message]=true end
end
local function releaseSound(sound)
    if not sound or sound.released then return end
    sound.released=true
    if sound.emitter then
        if sound.handle then pcall(function() sound.emitter:stopSoundLocal(sound.handle) end) end
        pcall(function() getWorld():returnOwnershipOfEmitter(sound.emitter) end)
    end
end
function C.selfKey() return B.playerKey(getPlayer()) end
function C.me(s)
    for _,m in ipairs(s and s.members or {}) do if m.id==C.selfKey() then return m end end
end
function C.getSession() return C.active and C.sessions[C.active] end
function C.serverNow(s)
    local schedule=s and C.schedules[s.id]
    local offset=(schedule and schedule.round==s.round and schedule.offset)
        or (s and s.id==C.active and C.lockOffset) or C.clockOffset
    return B.now()+offset
end
function C.elapsed(s) return C.serverNow(s)-s.startsAt end
function C.isPlaying(s)
    return s and (s.phase=='playing' or s.phase=='countdown') and C.elapsed(s)>=0
end
function C.send(command,args)
    local p=getPlayer()
    if not p then return end
    args=args or {};args.protocol=B.protocol
    if isClient() then sendClientCommand(p,B.module,command,args)
    elseif HUNKBandServer then HUNKBandServer.handle(command,p,args)
    else C.status='Band server code has not loaded. Check the mod installation.' end
end
function C.ping()
    C.nonce=C.nonce+1
    local nonce=tostring(C.nonce)
    C.pings[nonce]=B.now();C.lastPing=B.now()
    C.send('ping',{nonce=nonce})
end
function C.nearby(maxDist)
    local p=getPlayer();local list={}
    if not p then return list end
    local limit=tonumber(maxDist) or B.joinRadius
    for _,s in pairs(C.sessions) do
        if s.phase=='lobby' and #s.members<B.maxPlayers and B.distance(B.point(p),s)<=limit then
            list[#list+1]=s
        end
    end
    table.sort(list,function(a,b) return a.id<b.id end)
    return list
end
local function localSound(point,name,radius,gainPoint,forceGain)
    local emitter,handle
    if GameSounds and not GameSounds.isKnownSound(name) then
        audioFailure(name,'sound definition missing; restart after installing v0.10.0')
        return nil,nil
    end
    local ok,err=pcall(function()
        -- Own and tick this emitter explicitly: creating a paused native channel
        -- alone does not make it audible. The world must not tick/pool it as well.
        emitter=getWorld():getFreeEmitter(point.x,point.y,point.z)
        if emitter then
            getWorld():takeOwnershipOfEmitter(emitter)
            handle=emitter:playSoundImpl(name,false,nil)
            if handle and handle~=0 then
                emitter:set3D(handle,true)
                local gain=forceGain
                if gain==nil then gain=B.audioGain(gainPoint or point,B.point(getPlayer()),radius) end
                emitter:setVolume(handle,gain)
                emitter:tick()
            end
        end
    end)
    if not ok or not emitter or not handle or handle==0 then
        releaseSound({emitter=emitter,handle=handle})
        audioFailure(name,ok and 'engine returned no sound handle; check asset loading' or tostring(err))
        return nil,nil
    end
    return emitter,handle
end
local function mixSound(sound,point,radius)
    if not sound.emitter or not sound.handle or sound.failed then return end
    local ok=pcall(function()
        sound.emitter:setVolume(sound.handle,B.audioGain(point,B.point(getPlayer()),radius)*(sound.gain or 1))
        sound.emitter:setPos(point.x,point.y,point.z)
        sound.emitter:tick()
    end)
    if not ok then
        sound.failed=true;releaseSound(sound)
        audioFailure('playback','spatial emitter update failed')
    end
end
function C.prepareAudio(songId)
    if C.preparedAudio[songId] then return true end
    if B.now()<(C.audioRetryAt[songId] or 0) then return false end
    C.audioRetryAt[songId]=B.now()+2000
    local p=getPlayer()
    if not p then return false end
    local name=B.resolveSoundName(B.song(songId))
    -- Load/cache the actual PCM file before the scheduled start, muted, then
    -- release its warm-up voice immediately. No AI sound is generated here.
    local emitter,handle=localSound(B.point(p),name,16,nil,0)
    if not emitter or not handle then return false end
    releaseSound({emitter=emitter,handle=handle})
    C.preparedAudio[songId]=true;C.audioError=nil
    print('[Zomb-Band AUDIO] prepared '..name)
    return true
end
function C.prepareTrack(s,me)
    if isClient() and #C.samples<3 then return nil end
    if not C.prepareAudio(s.song) then return nil end
    local ok,stamp=pcall(B.preparationStamp,s,me)
    if not ok or not stamp then C.prepareError='Unable to prepare this instrument chart.';C.status=C.prepareError;return nil end
    C.prepareError=nil;C.audioError=nil;return stamp
end
function C.preparedCount(s)
    local count=0
    for _,member in ipairs(s and s.members or {}) do
        local stamp=B.preparationStamp(s,member)
        if stamp and member.ready and member.readyStamp==stamp then count=count+1 end
    end
    return count
end
function C.testAudio()
    local p=getPlayer();if not p then return end
    releaseSound(C.testVoice)
    local point=B.point(p)
    local emitter,handle=localSound(point,'ZB_AudioTest',16)
    if emitter and handle then
        C.testVoice={emitter=emitter,handle=handle,point=point,untilAt=B.now()+1000}
        C.audioError=nil;C.status='Test tone started on the effects channel. If silent, check game Sound volume.'
        print('[Zomb-Band AUDIO] test channel '..tostring(handle)..' emitter '..tostring(emitter))
    end
end
function C.stopPreview() releaseSound(C.previewVoice);C.previewVoice=nil end
function C.previewAudio(songId)
    if not B.songs[songId] or C.isPlaying(C.getSession()) then return false end
    local p=getPlayer();if not p then return false end
    C.stopPreview();local point=B.point(p)
    local emitter,handle=localSound(point,B.resolveSoundName(B.song(songId)),16,nil,.35)
    if not emitter or not handle then return false end
    C.previewVoice={emitter=emitter,handle=handle,point=point,song=songId,gain=.35,untilAt=B.now()+10000}
    C.status='Previewing the opening 10 seconds. Preview is local and attracts no zombies.'
    return true
end
function C.playNote(s,point,name)
    if not s or B.audioGain(s,B.point(getPlayer()),s.audibleRadius)<=0 then return end
    local emitter,handle=localSound(point,name,s.audibleRadius,s)
    if emitter and handle then
        C.effects[#C.effects+1]={id=s.id,point=point,emitter=emitter,handle=handle,untilAt=B.now()+1000}
    end
end
function C.stopBacking(id)
    local sound=C.audio[id]
    releaseSound(sound)
    C.audio[id]=nil
end
function C.walk(s,me)
    if not me or me.slot==1 or s.phase~='lobby' then return end
    local key=s.id..':'..me.slot
    if C.autoWalked[key] then return end
    C.autoWalked[key]=true
    pcall(function()
        local p=getPlayer()
        local square=getCell():getGridSquare(me.x,me.y,me.z)
        if square and ISWalkToTimedAction and ISTimedActionQueue and B.distance(B.point(p),me)>1.2 then
            ISTimedActionQueue.add(ISWalkToTimedAction:new(p,square))
        end
    end)
end
function C.resetRound(s)
    C.stopPreview();HUNKBandLibrary.beginRound(s,C.me(s))
    HUNKBandAnimation.stop(C)
    C.roundKey=s.id..':'..s.round;C.lockOffset=C.clockOffset
    C.base=B.newPerformance();C.state=B.newPerformance();C.pending={};C.seq=0;C.ackSeq=0
    C.noteSounds={};C.lastJudgement='';C.laneFlashes={};C.missFlashAt=nil;C.failureAt=nil
    C.animationBlocked=nil
end
function C.rebuild()
    local s=C.getSession();local me=C.me(s)
    if not me then return end
    local notes=B.notes(s.song,me.kind,me.difficulty)
    C.state=B.copy(C.base)
    for _,input in ipairs(C.pending) do B.input(C.state,notes,input.at,input.lane,me.difficulty) end
    if C.isPlaying(s) then B.expire(C.state,notes,C.elapsed(s)+C.calibration,me.difficulty) end
end
function C.receive(command,data)
    if type(data)~='table' then return end
    if data.protocol~=B.protocol then C.status='Zomb-Band version mismatch. Install v0.10.0 everywhere.';return end
    if command=='pong' then
        local sent=C.pings[tostring(data.nonce)]
        if not sent then return end
        C.pings[tostring(data.nonce)]=nil
        local received=B.now();local rtt=received-sent
        if rtt<0 or rtt>2000 or type(data.serverAt)~='number' then return end
        C.samples[#C.samples+1]={rtt=rtt,offset=data.serverAt-(sent+received)/2}
        if #C.samples>8 then table.remove(C.samples,1) end
        local best=C.samples[1]
        for _,sample in ipairs(C.samples) do if sample.rtt<best.rtt then best=sample end end
        C.clockOffset=best.offset;C.rtt=best.rtt
    elseif command=='sessions' then
        -- Replace the lobby cache; retain in-progress performances for audio.
        for id,s in pairs(C.sessions) do if s.phase=='lobby' and id~=C.active then C.sessions[id]=nil end end
        for _,s in ipairs(data.sessions or {}) do
            s.protocol=B.protocol;C.receive('sync',s)
        end
    elseif command=='sync' and data.id then
        C.sessions[data.id]=data
        if data.phase=='countdown' or data.phase=='playing' then
            local schedule=C.schedules[data.id]
            if (not schedule or schedule.round~=data.round) and (not isClient() or #C.samples>=3) then
                C.schedules[data.id]={round=data.round,offset=C.clockOffset}
            end
        end
        local me=C.me(data)
        if me and (data.host~=C.selfKey() or C.autoAdvanceSong and data.phase=='lobby') then
            HUNKBandLibrary.selected=data.song;C.song=data.song;C.autoAdvanceSong=nil
        end
        if data.phase=='results' and me then
            HUNKBandLibrary.finish(data,me)
            local token=data.id..':'..data.round
            if data.host==C.selfKey() and #(data.setlist or {})>0 and C.advanceToken~=token and C.window then
                C.advanceToken=token;C.startWhenReady=true;C.autoAdvanceSong=true;C.send('advance',{id=data.id})
            end
        end
        if data.phase=='countdown' and not me and not B.song(data.song).videoID then C.prepareAudio(data.song) end
        if me then
            C.itemType=me.itemType or C.itemType
            C.active=data.id
            if data.phase=='lobby' and C.nextPerformance and C.nextPerformance.id==data.id then
                local nextSong=C.nextPerformance;C.nextPerformance=nil;C.autoAdvanceSong=nil
                C.startWhenReady=true;C.song=nextSong.song;C.difficulty=nextSong.difficulty
                if nextSong.difficulty~=me.difficulty then C.send('difficulty',{id=data.id,difficulty=nextSong.difficulty}) end
                if nextSong.song~=data.song then C.send('song',{id=data.id,song=nextSong.song}) end
                C.status='Preparing the next song. Waiting for the band to sync...'
            end
            if data.phase=='lobby' or data.phase=='countdown' then C.prepareAudio(data.song) end
            if data.phase=='countdown' or data.phase=='playing' then
                local roundKey=data.id..':'..data.round
                if C.roundKey~=roundKey then C.resetRound(data) end
                if C.ensureWindow then C.ensureWindow(me.itemType) end
            elseif data.phase=='lobby' then C.lockOffset=nil end
            C.walk(data,me)
            if C.pendingAction then C.pendingAction=nil;C.status='Band ready. Choose a song, then play.' end
        elseif C.active==data.id then
            HUNKBandAnimation.stop(C)
            C.active=nil;C.lockOffset=nil
            C.status='You are no longer in that band.'
        end
    elseif command=='state' then
        local s=C.getSession()
        if not s or data.id~=s.id or data.round~=s.round then return end
        if C.roundKey~=s.id..':'..s.round and s.round>0 then C.resetRound(s) end
        if data.seq<(C.ackSeq or 0) then return end
        C.ackSeq=data.seq;C.seq=math.max(C.seq,data.seq);C.base=B.unpackPerformance(data.state)
        local pending={}
        for _,input in ipairs(C.pending) do if input.seq>data.seq then pending[#pending+1]=input end end
        C.pending=pending
        if data.verdict and data.verdict.judgement=='rejected' then
            C.lastJudgement='INPUT REJECTED - check connection';C.lastJudgementAt=B.now()
        end
        C.rebuild()
    elseif command=='note' then
        local p=getPlayer()
        local session=C.sessions[data.id]
        if not p or not session or data.round~=session.round then return end
        local token=tostring(data.round)..':'..tostring(data.seq)
        if data.player==C.selfKey() and C.noteSounds[token] then return end
        local family=B.soundNames[data.kind]
        if family then C.playNote(session,data,'HB_'..family..'_'..tostring(data.lane)) end
    elseif command=='remove' then
        C.stopBacking(data.id);C.sessions[data.id]=nil;C.schedules[data.id]=nil
        if C.active==data.id then
            HUNKBandAnimation.stop(C);C.active=nil;C.lockOffset=nil
            C.status='Band closed. Choose a song to play again.'
        end
    elseif command=='failed' then
        local s=C.getSession()
        if not s or s.id~=data.id or s.round~=data.round then return end
        if C.playFailureCue then C.playFailureCue(s) end
        HUNKBandAnimation.stop(C);HUNKBandCamera.stop()
        C.active=nil;C.lockOffset=nil;C.performanceEntered=nil;C.pending={};C.startWhenReady=false
        C.nextPerformance=nil;C.autoAdvanceSong=nil
        C.failureAt=B.now();C.failureScore=data.score or 0
        C.status='PERFORMANCE FAILED - '..C.failureScore..' points. Choose a track and press PLAY SOLO to retry.'
    elseif command=='error' then C.status=tostring(data.message);C.pendingAction=nil;C.startWhenReady=false end
end
local function reduceMoodStats(player,mult)
    if not player then return end
    local scale=mult or 1.0
    pcall(function()
        local stats=player.getStats and player:getStats()
        if stats and CharacterStat then
            if CharacterStat.BOREDOM and stats.get and stats.set then
                stats:set(CharacterStat.BOREDOM,math.max(0,(stats:get(CharacterStat.BOREDOM) or 0)-1.8*scale))
            end
            if CharacterStat.UNHAPPINESS and stats.get and stats.set then
                stats:set(CharacterStat.UNHAPPINESS,math.max(0,(stats:get(CharacterStat.UNHAPPINESS) or 0)-1.4*scale))
            end
            if CharacterStat.STRESS and stats.get and stats.set then
                stats:set(CharacterStat.STRESS,math.max(0,(stats:get(CharacterStat.STRESS) or 0)-0.012*scale))
            end
        end
    end)
    pcall(function()
        local bd=player.getBodyDamage and player:getBodyDamage()
        if bd then
            if bd.getBoredomLevel and bd.setBoredomLevel then
                bd:setBoredomLevel(math.max(0,(bd:getBoredomLevel() or 0)-1.8*scale))
            end
            if bd.getUnhappynessLevel and bd.setUnhappynessLevel then
                bd:setUnhappynessLevel(math.max(0,(bd:getUnhappynessLevel() or 0)-1.4*scale))
            end
        end
    end)
end
function C.awardPlayProgress(session,me,judgement,isFinish,accuracy)
    local p=getPlayer and getPlayer()
    if not p or not B.addMusicXP then return false,0 end
    local members=(session and session.members) and #session.members or 1
    local groupMult=1+0.25*math.max(0,members-1)
    local xp=0
    if isFinish then
        xp=math.max(10,math.floor((me and me.hits or 0)*0.35+(accuracy or 0)*0.25))*groupMult
        reduceMoodStats(p,2.5)
    elseif judgement=='perfect' or judgement=='good' then
        local base=(judgement=='perfect') and 1.15 or 0.75
        xp=base*groupMult
        C.xpHitCount=(C.xpHitCount or 0)+1
        if C.xpHitCount%8==0 then reduceMoodStats(p,1.0) end
    else
        return false,0
    end
    local leveledUp,newLevel=B.addMusicXP(p,xp)
    if HaloTextHelper and HaloTextHelper.addGoodText then
        if leveledUp then
            pcall(HaloTextHelper.addGoodText,p,'Musica Nvl. '..tostring(newLevel))
        elseif isFinish or (C.xpHitCount and C.xpHitCount%16==0) then
            pcall(HaloTextHelper.addGoodText,p,isFinish and string.format('+%.0f XP Musica',xp) or '+XP Musica')
        end
    end
    return leveledUp,newLevel
end
function C.hit(lane)
    local s=C.getSession();local me=C.me(s)
    if not C.isPlaying(s) or not me or lane>B.difficulty(me.difficulty).lanes then return end
    local at=C.elapsed(s)+C.calibration
    if at>B.song(s.song).durationMs+B.difficulty(me.difficulty).window then return end
    C.seq=C.seq+1
    local input={seq=C.seq,at=at,lane=lane}
    C.pending[#C.pending+1]=input
    local verdict=B.input(C.state,B.notes(s.song,me.kind,me.difficulty),at,lane,me.difficulty)
    C.lastJudgement=string.upper(verdict.judgement);C.lastJudgementAt=B.now()
    C.laneFlashes=C.laneFlashes or {};C.laneFlashes[lane]={at=B.now(),hit=verdict.index~=nil}
    if verdict.index then
        C.awardPlayProgress(s,me,verdict.judgement,false)
        if B.song(s.song).hitSounds~=false then
            C.noteSounds[tostring(s.round)..':'..C.seq]=true
            C.playNote(s,B.point(getPlayer()),'HB_'..B.soundNames[me.kind]..'_'..lane)
        end
    end
    C.send('input',{id=s.id,round=s.round,seq=input.seq,at=at,lane=lane})
end
local UI=ISPanel:derive('HUNKBandUI')
function UI:new()
    local w,h=680,560
    local o=ISPanel:new(math.max(0,(getCore():getScreenWidth()-w)/2),math.max(0,(getCore():getScreenHeight()-h)/2),w,h)
    setmetatable(o,self);self.__index=self;o.moveWithMouse=true;o.background=false
    o:setWantKeyEvents(true)
    return o
end
function UI:initialise() ISPanel.initialise(self) end
local function button(self,x,y,w,label,callback)
    local b=ISButton:new(x,y,w,28,label,self,callback)
    b:initialise();b:instantiate();self:addChild(b);return b
end
function UI:createChildren()
    if self.closeBtn then return end
    self.closeBtn=button(self,635,9,30,'X',UI.closeWindow)
    self.songBox=ISComboBox:new(140,66,370,26,self,UI.chooseSong)
    self.songBox:initialise();self.songBox:instantiate();self:addChild(self.songBox)
    for _,song in ipairs(B.songs) do self.songBox:addOption(song.name) end
    self.songBox.selected=C.song
    self.diffBox=ISComboBox:new(140,104,200,26,self,UI.chooseDifficulty)
    self.diffBox:initialise();self.diffBox:instantiate();self:addChild(self.diffBox)
    for _,d in ipairs(B.difficulties) do self.diffBox:addOption(d.name..' - '..d.lanes..' lanes') end
    self.diffBox.selected=C.difficulty
    self.bandBox=ISComboBox:new(140,150,370,26,self,nil)
    self.bandBox:initialise();self.bandBox:instantiate();self:addChild(self.bandBox)
    self.playBtn=button(self,16,518,115,'PLAY SONG',UI.play)
    self.formBtn=button(self,140,518,115,'FORM BAND',UI.form)
    self.joinBtn=button(self,264,518,115,'JOIN BAND',UI.join)
    self.replayBtn=button(self,140,518,145,'BACK TO SONGS',UI.replay)
    self.leaveBtn=button(self,540,518,125,'LEAVE / CLOSE',UI.exitBand)
    self.minusBtn=button(self,370,104,32,'-',UI.lessOffset)
    self.plusBtn=button(self,525,104,32,'+',UI.moreOffset)
    self.audioTestBtn=button(self,538,66,127,'AUDIO TEST',UI.audioTest)
    self.cameraBtn=button(self,16,518,134,'CAMERA ON',UI.cameraToggle)
    self.focusBtn=button(self,158,518,134,'FOCUS: BAND',UI.focusToggle)
    self.cutBtn=button(self,300,518,105,'NEXT SHOT',UI.nextCamera)
    self.hudPosBtn=button(self,412,518,118,'HUD: CENTER',UI.toggleHudPos)
    self.cameraBtn:setVisible(false);self.focusBtn:setVisible(false);self.cutBtn:setVisible(false);self.hudPosBtn:setVisible(false)
end
function UI:toggleHudPos()
    C.hudCentered=not C.hudCentered
    if self.hudPosBtn then self.hudPosBtn:setTitle(C.hudCentered and 'HUD: CENTER' or 'HUD: SIDE') end
end
function UI:audioTest() C.testAudio() end
function UI:chooseSong()
    local s=C.getSession()
    C.song=self.songBox.selected
    HUNKBandLibrary.selected=C.song
    if s and s.phase=='lobby' and s.host==C.selfKey() and s.song~=C.song then
        C.startWhenReady=false;C.send('song',{id=s.id,song=C.song})
    end
end
function UI:chooseDifficulty()
    C.difficulty=self.diffBox.selected
    local s=C.getSession()
    if s and s.phase=='lobby' then C.startWhenReady=false;C.send('difficulty',{id=s.id,difficulty=C.difficulty}) end
end
function UI:lessOffset() C.calibration=math.max(-150,C.calibration-10) end
function UI:moreOffset() C.calibration=math.min(150,C.calibration+10) end
function UI:form()
    if C.pendingAction or C.getSession() then return end
    if not HUNKBandLibrary.selected then C.status='Select a song first.';return end
    local curKind=self:libraryKind()
    local songObj=B.song(HUNKBandLibrary.selected)
    if not B.songAllowsKind(songObj,curKind) then
        C.status='Instrumento no incluido en "'..tostring(songObj.name)..'". Usa: '..B.allowedInstrumentLabel(songObj)
        return
    end
    HUNKBandLibrary.select(HUNKBandLibrary.selected,C)
    C.pendingAction=B.now();C.status='Creating band...'
    C.send('create',{itemType=C.itemType,role=C.roleOverride,song=C.song,difficulty=C.difficulty})
end
function UI:play()
    C.stopPreview()
    local s=C.getSession()
    if s and s.phase=='lobby' and s.host==C.selfKey() and C.startWhenReady then
        C.startWhenReady=false;C.status='Start cancelled. The band stays in the lobby.';return
    end
    local curKind=self:libraryKind()
    if HUNKBandLibrary.selected and not B.songAllowsKind(HUNKBandLibrary.selected,curKind) then
        local songObj=B.song(HUNKBandLibrary.selected)
        C.status='Este instrumento ('..(B.kindNames[curKind] or curKind)..') no toca en "'..tostring(songObj.name)..'". Solo: '..B.allowedInstrumentLabel(songObj)
        return
    end
    if HUNKBandLibrary.selected and not B.playable(HUNKBandLibrary.selected,curKind,C.difficulty) then C.status='Selected song has no playable chart.';return end
    if not HUNKBandLibrary.selected then C.status='No song selected. Clear the search or change collection.';return end
    if s and s.host~=C.selfKey() then C.status='The band leader starts the song.';return end
    if s and s.phase=='results' then
        C.nextPerformance={id=s.id,song=HUNKBandLibrary.selected,difficulty=C.difficulty}
        C.startWhenReady=false;C.status='Resetting the band for the selected song...'
        C.send('replay',{id=s.id});return
    end
    if not s then HUNKBandLibrary.select(HUNKBandLibrary.selected,C)
    elseif s.phase=='lobby' and HUNKBandLibrary.selected and HUNKBandLibrary.selected~=s.song then
        HUNKBandLibrary.select(HUNKBandLibrary.selected,C)
        C.startWhenReady=true;C.status='Preparing the selected track. Waiting for the band...';return
    end
    if not s and not B.song(C.song).videoID and not C.prepareAudio(C.song) then C.startWhenReady=false;return end
    C.startWhenReady=true;C.status='Preparing song. Waiting for all band members...';
    if not s then self:form() end
end
function UI:join()
    if C.getSession() or C.pendingAction then return end
    local id=self.bandIds and self.bandIds[self.bandBox.selected]
    if not id then C.status='No nearby waiting band. Have a friend choose FORM BAND.';C.send('discover');return end
    local band=C.sessions[id]
    local curKind=self:libraryKind()
    if band and not B.songAllowsKind(band.song,curKind) then
        local bandSong=B.song(band.song)
        C.status='Sala Sound Group: "'..tostring(bandSong.name)..'" solo permite: '..B.allowedInstrumentLabel(bandSong)
        return
    end
    C.pendingAction=B.now();C.status='Joining band...';C.startWhenReady=false
    C.send('join',{id=id,itemType=C.itemType,role=C.roleOverride,difficulty=C.difficulty})
end
function UI:replay()
    local s=C.getSession();if s then C.send('replay',{id=s.id}) end
end
function UI:closeWindow()
    local s=C.getSession()
    if s and s.phase=='lobby' and not C.startWhenReady then
        C.stopPreview()
        if self.joyfocus and setJoypadFocus then setJoypadFocus(0,nil) end
        self:removeFromUIManager();C.window=nil
        return
    end
    self:exitBand()
end
function UI:exitBand()
    C.stopPreview()
    HUNKBandCamera.stop();C.performanceEntered=nil
    HUNKBandAnimation.stop(C)
    local s=C.getSession()
    if s then
        C.send('leave',{id=s.id})
    end
    C.active=nil;C.lockOffset=nil;C.startWhenReady=false;C.pendingAction=nil;C.nextPerformance=nil;HUNKBandLibrary.queue={}
    if self.joyfocus and setJoypadFocus then setJoypadFocus(0,nil) end
    self:removeFromUIManager();C.window=nil
end
local colors={{0.25,0.85,0.35},{0.92,0.25,0.25},{0.96,0.83,0.25},{0.3,0.55,0.95},{0.96,0.54,0.22}}
function UI:prerender()
    if HUNKBandCamera.testUntil then
        self:layoutPerformance(true)
        for _,name in ipairs({'songBox','diffBox','audioTestBtn','minusBtn','plusBtn','bandBox','playBtn','formBtn','joinBtn','replayBtn','leaveBtn','cameraBtn','focusBtn','cutBtn'}) do self[name]:setVisible(false) end
        self.closeBtn:setVisible(true)
        self:drawRect(14,14,math.min(650,self.width-70),80,.85,.02,.05,.09)
        self:drawText('CAMERA CHECK / ESC TO RETURN',28,24,.35,.83,1,1,UIFont.Medium)
        self:drawText(HUNKBandCamera.label:sub(1,88),28,54,.85,.92,1,1,UIFont.Small)
        return
    end
    local s=C.getSession();local me=C.me(s)
    local performing=s and me and (s.phase=='playing' or s.phase=='countdown') and C.elapsed(s)<B.song(s.song).durationMs
    self:layoutPerformance(performing~=nil and performing~=false)
    if performing then
        for _,name in ipairs({'closeBtn','leaveBtn','cameraBtn','focusBtn','cutBtn'}) do self[name]:setVisible(true) end
        for _,child in ipairs({self.songBox,self.diffBox,self.audioTestBtn,self.minusBtn,self.plusBtn,self.bandBox,self.playBtn,self.formBtn,self.joinBtn,self.replayBtn}) do child:setVisible(false) end
        self:drawPerformance(s,me)
    else self:drawMenu(s,me) end
end
function C.ensureWindow(itemType)
    if itemType then C.itemType=itemType end
    if C.window then
        C.window.librarySignature=nil
        C.window:refreshLibrary()
        C.window:bringToTop()
        return C.window
    end
    HUNKBandLibrary.selected=C.getSession() and C.getSession().song or C.song
    C.window=UI:new();C.window:initialise();C.window:addToUIManager();C.window:bringToTop();C.window:refreshLibrary()
    if JoypadState and JoypadState.players and JoypadState.players[1] and setJoypadFocus then setJoypadFocus(0,C.window) end
    return C.window
end
function C.open(item)
    if not item then return end
    C.itemType=item:getFullType();C.status='Browse the library. Select a track, then PLAY SOLO or FORM BAND.'
    C.send('discover');C.lastDiscover=B.now()
    C.ensureWindow(C.itemType)
end
function C.findBestItemForKind(player,targetKind,fallbackType)
    if targetKind and fallbackType and B.instrumentKind(fallbackType)==targetKind and B.hasInstrument(player,fallbackType,4.0) then
        return fallbackType
    end
    if targetKind and player then
        for fullType,kind in pairs(B.vanillaInstruments) do
            if kind==targetKind and B.hasInstrument(player,fullType,4.0) then return fullType end
        end
        for fullType,kind in pairs(B.instrumentOverrides or {}) do
            if kind==targetKind and B.hasInstrument(player,fullType,4.0) then return fullType end
        end
    end
    return nil
end
function C.bestItemForRole(player,roleId,fallbackType)
    local targetKind=B.roleToKind and B.roleToKind[roleId]
    local found=C.findBestItemForKind(player,targetKind,fallbackType)
    return found or fallbackType
end
function C.openSolo(item)
    if not item then return end
    local s=C.getSession()
    if s and (s.phase=='lobby' or s.phase=='results') and #s.members>1 then
        C.send('leave',{id=s.id});C.active=nil
    end
    C.roleOverride=nil
    C.itemType=item:getFullType()
    C.soloMode=true
    C.open(item)
    local kind=B.instrumentKind(C.itemType) or 'acoustic'
    C.status='Modo Solista ('..(B.kindNames[kind] or kind)..'): elige una cancion y presiona PLAY SOLO.'
end
function C.createBandWithRole(player,item,roleId)
    if not player or not item then return end
    local targetKind=(B.roleToKind and B.roleToKind[roleId]) or B.instrumentKind(item:getFullType())
    local songId=HUNKBandLibrary.selected or C.song or 1
    if not B.playable(songId,targetKind,C.difficulty) then
        for id=1,#B.songs do
            if B.playable(id,targetKind,C.difficulty) and B.isSoundAvailable(B.songs[id]) then
                songId=id;HUNKBandLibrary.selected=id;break
            end
        end
    end
    local chosenItem=C.bestItemForRole(player,roleId,item:getFullType())
    C.roleOverride=roleId
    C.soloMode=false
    C.itemType=chosenItem
    C.ensureWindow(chosenItem)
    local s=C.getSession()
    if s then
        if s.phase=='lobby' or s.phase=='results' then
            C.send('instrument',{id=s.id,itemType=chosenItem,role=roleId})
            C.status='Rol de banda actualizado. Espera a tus amigos y elige cancion.'
        end
        return
    end
    C.song=songId
    C.pendingAction=B.now()
    C.status='Creando Sala de Banda...'
    C.send('create',{itemType=chosenItem,role=roleId,song=songId,difficulty=C.difficulty})
end
function C.joinBandWithRole(player,item,bandId,roleId)
    if not player or not item or not bandId then return end
    local s=C.getSession()
    if s and s.id~=bandId then
        C.send('leave',{id=s.id});C.active=nil
    end
    local targetBand=C.sessions[bandId]
    local targetKind=(B.roleToKind and B.roleToKind[roleId]) or B.instrumentKind(item:getFullType())
    local chosenItem=C.bestItemForRole(player,roleId,item:getFullType())
    C.roleOverride=roleId
    C.soloMode=false
    C.itemType=chosenItem
    C.ensureWindow(chosenItem)
    if targetBand and not B.songAllowsKind(targetBand.song,targetKind) then
        local bandSong=B.song(targetBand.song)
        C.status='Sala Sound Group: "'..tostring(bandSong.name)..'" solo permite: '..B.allowedInstrumentLabel(bandSong)
        return
    end
    if s and s.id==bandId then
        C.send('instrument',{id=bandId,itemType=chosenItem,role=roleId})
        C.status='Rol actualizado en la Sala de Banda.'
        return
    end
    C.pendingAction=B.now()
    C.startWhenReady=false
    C.status='Uniendose a la Sala de Banda...'
    C.send('join',{id=bandId,itemType=chosenItem,role=roleId,difficulty=C.difficulty})
end
local function unwrap(entry)
    if instanceof(entry,'InventoryItem') then return entry end
    if type(entry)=='table' and entry.items then
        for _,item in ipairs(entry.items) do if instanceof(item,'InventoryItem') then return item end end
    end
end
function C.populateInstrumentMenu(p,context,item,worldSquare)
    if not p or not context or not item then return end
    local fullType=item:getFullType()
    local kind=B.instrumentKind(fullType)
    if not kind then return end
    if B.now()-C.lastDiscover>=1500 then C.lastDiscover=B.now();C.send('discover') end

    local rockOpt=context:addOption('Rock Out...',nil,function() C.roleOverride=nil;C.open(item) end)
    local soloOpt=context:addOption('Tocar Solo',nil,function() C.openSolo(item) end)
    if ISToolTip then
        pcall(function()
            local skill=B.musicSkill and B.musicSkill(p) or {level=0,xp=0}
            local desc=string.format('Nivel de Musica: %d / 10 (XP: %.0f) <LINE> Tocar solo o en banda sube tu nivel de Musica y reduce Aburrimiento e Infelicidad.',skill.level or 0,skill.xp or 0)
            for _,opt in ipairs({rockOpt,soloOpt}) do
                local t=ISToolTip:new()
                t:initialise();t:setVisible(false)
                t:setName(B.kindNames[kind] or 'Instrumento')
                t.description=desc
                opt.toolTip=t
            end
        end)
    end

    if ISContextMenu and ISContextMenu.getNew then
        local defaultRole=B.kindNames[kind] and kind or (B.chartRole and B.chartRole(kind) or 'lead')
        local createSub=ISContextMenu:getNew(context)
        local createOpt=context:addOption('Crear Sala de Banda')
        context:addSubMenu(createOpt,createSub)
        local selSong=B.song(HUNKBandLibrary and HUNKBandLibrary.selected or C.song or 1)
        for _,role in ipairs(B.bandRoles or {}) do
            local allowedForSel=B.songAllowsKind(selSong,role.kind)
            local isCurrent=(role.kind==kind)
            if isCurrent or role.id=='lead' or role.id=='rhythm' or role.id=='bass' or role.id=='drums' or role.id=='vocals' or allowedForSel then
                local suffix=isCurrent and ' [Instrumento actual]' or (not allowedForSel and ' [No en "'..tostring(selSong.name)..'"]' or '')
                local opt=createSub:addOption(role.label..suffix,nil,function()
                    C.createBandWithRole(p,item,role.id)
                end)
                if not allowedForSel then opt.notAvailable=true end
            end
        end

        local joinSub=ISContextMenu:getNew(context)
        local nearby=C.nearby(B.bandRoomRadius or 8)
        local joinLabel=#nearby>0 and ('Unirse a Sala de Banda ('..#nearby..' en 8 casillas)') or 'Unirse a Sala de Banda (8 casillas)'
        local joinOpt=context:addOption(joinLabel)
        context:addSubMenu(joinOpt,joinSub)
        local function addJoinRoles(targetMenu,band)
            local bandSong=B.song(band.song)
            local hostName=band.members and band.members[1] and band.members[1].name or 'Lider'
            local h1=targetMenu:addOption('Sala de '..hostName..' ('..#band.members..'/'..B.maxPlayers..') - '..tostring(bandSong.name))
            h1.notAvailable=true
            local h2=targetMenu:addOption('Solo instrumentos de la cancion: '..B.allowedInstrumentLabel(bandSong,6))
            h2.notAvailable=true
            for _,role in ipairs(B.bandRoles or {}) do
                if B.songAllowsKind(bandSong,role.kind) then
                    local hasOwned=(role.kind==kind) or (C.findBestItemForKind(p,role.kind,fullType)~=nil)
                    local suffix=role.kind==kind and ' [Instrumento listo]' or (hasOwned and ' [Tienes instrumento]' or ' [Falta instrumento]')
                    local rOpt=targetMenu:addOption('Rol: '..role.label..suffix,nil,function()
                        C.joinBandWithRole(p,item,band.id,role.id)
                    end)
                    if not hasOwned then
                        rOpt.notAvailable=true
                        if ISToolTip then
                            pcall(function()
                                local t=ISToolTip:new();t:initialise();t:setVisible(false)
                                t:setName(B.kindNames[role.kind] or role.label)
                                t.description='Necesitas llevar o estar cerca de: '..tostring(B.kindNames[role.kind] or role.kind)..' <LINE> Cancion: '..tostring(bandSong.name)..' <LINE> Permitidos: '..B.allowedInstrumentLabel(bandSong)
                                rOpt.toolTip=t
                            end)
                        end
                    end
                end
            end
        end
        if #nearby==0 then
            joinSub:addOption('Buscar salas cercanas (8 casillas)...',nil,function()
                C.lastDiscover=B.now();C.send('discover')
                C.open(item)
            end)
        elseif #nearby==1 then
            addJoinRoles(joinSub,nearby[1])
        else
            for _,band in ipairs(nearby) do
                local hostName=band.members and band.members[1] and band.members[1].name or 'Lider'
                local bandSong=B.song(band.song)
                local bandOpt=joinSub:addOption('Sala de '..hostName..' - '..tostring(bandSong.name)..' ('..#band.members..'/'..B.maxPlayers..')')
                local roleSub=ISContextMenu:getNew(joinSub)
                joinSub:addSubMenu(bandOpt,roleSub)
                addJoinRoles(roleSub,band)
            end
        end
    end
end
function C.contextMenu(playerNum,context,items)
    if playerNum~=0 then return end -- one rhythm UI per machine; no split-screen claims
    local p=getSpecificPlayer(playerNum)
    if not p then return end
    for _,entry in ipairs(items or {}) do
        local item=unwrap(entry)
        if item and B.instrumentKind(item:getFullType()) then
            C.populateInstrumentMenu(p,context,item,nil)
            return
        end
    end
end
function C.worldContextMenu(playerNum,context,worldobjects,test)
    if test or playerNum~=0 then return end
    local p=getSpecificPlayer(playerNum)
    if not p then return end
    local checkedSquares={}
    local function tryWorldObj(wobj)
        if not wobj or not instanceof(wobj,'IsoWorldInventoryObject') then return nil,nil end
        local item=wobj.getItem and wobj:getItem()
        if item and B.instrumentKind(item:getFullType()) then
            local sq=wobj.getSquare and wobj:getSquare()
            return item,sq
        end
        return nil,nil
    end
    for _,obj in ipairs(worldobjects or {}) do
        local item,sq=tryWorldObj(obj)
        if item then C.populateInstrumentMenu(p,context,item,sq);return end
        local oSq=obj and obj.getSquare and obj:getSquare()
        if oSq and not checkedSquares[oSq] then
            checkedSquares[oSq]=true
            local list=oSq.getWorldObjects and oSq:getWorldObjects()
            if list then
                for i=0,list:size()-1 do
                    local it,wSq=tryWorldObj(list:get(i))
                    if it then C.populateInstrumentMenu(p,context,it,wSq);return end
                end
            end
        end
    end
end
function C.onKeyDown(key)
    if not C.window then return end
    local first=(Keyboard and Keyboard.KEY_1) or 2
    if key>=first and key<=first+4 then C.hit(key-first+1);return end
    if Keyboard then
        if key==Keyboard.KEY_A then C.hit(1)
        elseif key==Keyboard.KEY_S then C.hit(2)
        elseif key==Keyboard.KEY_D then C.hit(3)
        elseif key==Keyboard.KEY_F then C.hit(4)
        elseif key==Keyboard.KEY_G then C.hit(5)
        elseif key==Keyboard.KEY_SPACE then C.hit(1) end
    end
end
function UI:isKeyConsumed(key)
    local s=C.getSession()
    local first=(Keyboard and Keyboard.KEY_1) or 2
    if HUNKBandCamera.testUntil then return true end
    if self.searchEntry and self.searchEntry:isFocused() then return false end
    return true
end
function UI:onKeyPress(key)
    if not self:isKeyConsumed(key) then return end
    if HUNKBandCamera.testUntil then
        if key==1 then HUNKBandCamera.stop();C.status='Camera check cancelled. Previous view restored.' end
        if GameKeyboard then GameKeyboard.eatKeyPress(key) end
        return
    end
    local s=C.getSession()
    if not s or s.phase=='lobby' or s.phase=='results' then
        self:libraryKey(key)
        if GameKeyboard then GameKeyboard.eatKeyPress(key) end
        return
    end
    if key==((Keyboard and Keyboard.KEY_ESCAPE) or 1) then
        if GameKeyboard then GameKeyboard.eatKeyPress(key) end
        self:exitBand();return
    end
    C.onKeyDown(key)
    if GameKeyboard then GameKeyboard.eatKeyPress(key) end
end
-- Judge key-down once. Repeat and release must not produce another hit.
function UI:onKeyRepeat(key) end
function UI:onKeyRelease(key) end
function C.tick()
    local p=getPlayer()
    if not p then C.shutdown();return end
    local now=B.now()
    local interval=#C.samples<3 and 250 or 5000
    if now-C.lastPing>=interval then C.ping() end
    for nonce,sent in pairs(C.pings) do if now-sent>5000 then C.pings[nonce]=nil end end
    if (C.window or isClient()) and not C.isPlaying(C.getSession()) and now-C.lastDiscover>=3500 then C.lastDiscover=now;C.send('discover') end
    if C.pendingAction and now-C.pendingAction>8000 then
        C.pendingAction=nil;C.startWhenReady=false;C.status='Band request timed out. Check the server connection and try again.'
    end
    local s=C.getSession();local me=C.me(s)
    if s and me then
        if s.phase=='lobby' and s.host==C.selfKey() and C.startWhenReady and #HUNKBandLibrary.queue>0 then
            local queued=HUNKBandLibrary.queue;HUNKBandLibrary.queue={};C.send('setlist',{id=s.id,songs=queued})
        end
        if s.phase=='lobby' then
            local stamp=C.prepareTrack(s,me)
            if stamp and (not me.ready or me.readyStamp~=stamp) and now-(C.readySent or -10000)>1000 then
                C.readySent=now;C.send('ready',{id=s.id,stamp=stamp})
            elseif not stamp and me.ready and now-(C.readySent or -10000)>1000 then
                C.readySent=now;C.send('unready',{id=s.id})
            end
            if C.startWhenReady and s.host==C.selfKey() then
                local ready=C.preparedCount(s)
                if stamp and ready==#s.members and HUNKBandLibrary.selected==s.song and me.difficulty==C.difficulty then
                    C.startWhenReady=false;C.send('start',{id=s.id})
                elseif not C.audioError then C.status=C.prepareError or 'PREPARING SONG - '..ready..'/'..#s.members..' synced. Waiting for every musician; press CANCEL WAIT to stop.' end
            end
        end
        if C.isPlaying(s) then
            local missed=B.expire(C.state,B.notes(s.song,me.kind,me.difficulty),C.elapsed(s)+C.calibration,me.difficulty)
            if missed>0 then C.lastJudgement='MISS';C.lastJudgementAt=now;C.missFlashAt=now end
        end
    end
    if C.menuAudioUpdate then C.menuAudioUpdate() end
    HUNKBandAnimation.update(C,s,me)
    HUNKBandCamera.update(C,s,me)
    if C.previewVoice then
        if now>=C.previewVoice.untilAt or C.isPlaying(s) or not C.window then C.stopPreview()
        else mixSound(C.previewVoice,C.previewVoice.point,16) end
    end
    for id,session in pairs(C.sessions) do
        if not B.song(session.song).videoID and (session.phase=='countdown' or session.phase=='playing') then
            local schedule=C.schedules[id]
            local clockReady=not isClient() or #C.samples>=3
            if (not schedule or schedule.round~=session.round) and clockReady then
                C.schedules[id]={round=session.round,offset=C.clockOffset}
            end
            local elapsed=clockReady and C.elapsed(session) or -math.huge
            if elapsed>=0 and elapsed<B.song(session.song).durationMs and not C.audio[id] then
                local sound={round=session.round};C.audio[id]=sound
                if elapsed<=250 then
                    local soundName=B.resolveSoundName(B.song(session.song))
                    sound.emitter,sound.handle=localSound(session,soundName,session.audibleRadius)
                    if sound.handle then print('[Zomb-Band AUDIO] playing '..soundName..' round '..session.round..' offset '..math.floor(elapsed)..'ms') end
                elseif id==C.active then audioFailure(B.song(session.song).sound,'missed scheduled start; replay the song') end
            end
            if C.audio[id] then
                if elapsed>=B.song(session.song).durationMs then C.stopBacking(id)
                else mixSound(C.audio[id],session,session.audibleRadius) end
            end
        elseif C.audio[id] then C.stopBacking(id) end
    end
    for i=#C.effects,1,-1 do
        local effect=C.effects[i]
        local session=C.sessions[effect.id]
        if now>=effect.untilAt or not session or (session.phase~='playing' and session.phase~='countdown') then
            releaseSound(effect)
            table.remove(C.effects,i)
        elseif not effect.emitter:isPlaying(effect.handle) then releaseSound(effect);table.remove(C.effects,i)
        else mixSound(effect,session,session.audibleRadius) end
    end
    if C.testVoice then
        if now>=C.testVoice.untilAt then releaseSound(C.testVoice);C.testVoice=nil
        else mixSound(C.testVoice,C.testVoice.point,16) end
    end
end
function C.shutdown()
    if C.stopMenuAudio then C.stopMenuAudio() end
    C.stopPreview()
    HUNKBandCamera.stop();C.performanceEntered=nil
    if C.window then C.window:removeFromUIManager();C.window=nil end
    pcall(function() HUNKBandAnimation.stop(C) end)
    for id in pairs(C.audio) do C.stopBacking(id) end
    for _,effect in ipairs(C.effects) do releaseSound(effect) end
    C.effects={};releaseSound(C.testVoice);C.testVoice=nil
    C.active=nil;C.sessions={};C.schedules={};C.lockOffset=nil;C.roundKey=nil
    C.pending={};C.pendingAction=nil;C.startWhenReady=false;C.animationBlocked=nil;C.nextPerformance=nil;C.autoAdvanceSong=nil
end
require('HUNKBand_PerformanceUI')(UI,C,B,HUNKBandCamera)
require('HUNKBand_LibraryUI')(UI,C,B,HUNKBandCamera,HUNKBandLibrary)
require('HUNKBand_MenuAudio')(UI,C,B)
require('HUNKBand_CustomClient')(UI,C,B,HUNKBandLibrary)
Events.OnFillInventoryObjectContextMenu.Add(C.contextMenu)
if Events.OnFillWorldObjectContextMenu then Events.OnFillWorldObjectContextMenu.Add(C.worldContextMenu) end
Events.OnServerCommand.Add(function(module,command,data) if module==B.module then C.receive(command,data) end end)
Events.OnTick.Add(C.tick)
if Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(C.shutdown) end
if Events.OnDisconnect then Events.OnDisconnect.Add(C.shutdown) end
if Events.OnPostUIDraw then Events.OnPostUIDraw.Add(function()
    if C.failureAt and B.now()-C.failureAt<4000 and not C.window then
        local text=getTextManager();local x=getCore():getScreenWidth()/2
        text:DrawStringCentre(UIFont.Large,x,90,'PERFORMANCE FAILED',1,.25,.20,1)
        text:DrawStringCentre(UIFont.Medium,x,126,tostring(C.failureScore)..' POINTS  /  Rock Out again to retry',1,.90,.65,1)
    end
end) end
print('[Zomb-Band] v0.10.0 client loaded - author HUNK')

