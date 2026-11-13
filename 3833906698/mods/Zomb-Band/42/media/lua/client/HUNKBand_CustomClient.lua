-- Client presentation/downloads are separate from the authoritative custom-chart registry.
return function(UI,C,B,L)
    local U={mode=false,authorized={}};C.custom=U
    local function backend() return ZombBandMedia and ZombBandMedia.version and ZombBandMedia or nil end
    local function call(name,...)
        local api=backend();if not api then return nil,'Enable Zomb-Band - Custom Songs and ZombieBuddy, then restart the game.' end
        local args={...};local ok,value=pcall(function() return api[name](unpack(args)) end)
        if not ok then return nil,'Custom media bridge error: '..tostring(value) end
        return value
    end
    local function message(text) U.message=text;C.status=text end
    local function clearPlayback()
        if U.playing then call('stop');U.playing=nil end
    end
    function U.cancel()
        call('cancel');call('stop');U.playing=nil;U.suspended=true
        local s=C.getSession();if s and s.phase=='lobby' and B.song(s.song).videoID then C.send('unready',{id=s.id}) end
        U.pending=nil;U.upload=nil;U.failed=nil;U.retrying=nil;C.startWhenReady=false
        message('Custom preparation cancelled. No song has been started.')
    end
    function U.begin(urlOrPath)
        local s=C.getSession()
        if s and (s.host~=C.selfKey() or s.phase~='lobby') then message('Only the band leader can load a song in the waiting lobby.');return false end
        U.mode=true;U.suspended=false;C.startWhenReady=false;C.stopPreview()
        local raw=tostring(urlOrPath or ''):match('^%s*(.-)%s*$')
        if raw=='' then message('Paste an HTTPS YouTube URL or pick a local file from Zomboid/ZombBand/songs.');return false end
        local id=B.videoID(raw)
        local target=id and ('https://www.youtube.com/watch?v='..id) or raw
        local ok,err=call('begin',target)
        if not ok then message(err or call('error') or 'Unable to prepare this song or URL.');return false end
        id=id or call('requestedID')
        if not id or id=='' then message('Could not resolve custom song ID.');return false end
        U.authorized[id]=true;U.pending=id;U.upload=nil;U.failed=nil;message('Preparing custom audio & chart. The current library track will not start.');return true
    end
    function U.retry()
        local s=C.getSession();local song=s and B.songs[s.song]
        if not s or s.phase~='lobby' or not song or not song.videoID then message('No waiting custom track to retry.');return false end
        U.failed=nil;U.suspended=false;U.authorized[song.videoID]=true
        C.send('unready',{id=s.id});call('stop');U.retrying=song.videoID
        local ok,err=call('begin',song.url)
        if not ok then message(err or call('error') or 'Unable to retry this track.');return false end
        U.mode=false;message('Retrying the band track on this computer. The host still waits for matching audio.');return true
    end
    local oldSend=C.send
    function C.send(command,args)
        args=args or {};if command=='discover' then args.customRevision=B.customRevision end
        return oldSend(command,args)
    end
    local oldReceive=C.receive
    function C.receive(command,data)
        if command=='sync' and type(data)=='table' and data.protocol==B.protocol and C.me(data) then
            local song=B.songs[data.song];if song and song.videoID then U.authorized[song.videoID]=true end
        end
        if command=='customTrack' and type(data)=='table' and data.protocol==B.protocol then
            local id=B.installCustom(data)
            if not id then message('Custom catalog mismatch. Reconnect with the same Zomb-Band version.');return end
            L.revision=L.revision+1
            if U.upload and data.videoID==U.upload.videoID and data.audioHash==U.upload.audioHash and data.chartHash==U.upload.chartHash then
                U.pending=nil;U.upload=nil;U.mode=false;L.filter=1;L.query='';L.scroll=0
                if C.window then C.window.searchEntry:setText('');C.window.customURL:unfocus();C.window.librarySignature=nil end
                L.select(id,C);message('Custom track loaded. PLAY SOLO or START BAND waits for matching audio and charts on every musician.')
            end
            return
        end
        local result=oldReceive(command,data)
        if U.playing and not C.getSession() then clearPlayback() end
        if command=='error' and U.upload then U.upload=nil;U.pending=nil;message(C.status) end
        return result
    end
    local oldPrepare=C.prepareAudio
    function C.prepareAudio(id)
        local song=B.songs[id];if not song or not song.videoID then local ready=oldPrepare(id);if ready then C.audioError=nil end;return ready end
        if not U.authorized[song.videoID] or U.suspended then return false end
        local api=backend()
        if not api then C.audioError='Custom song requires Zomb-Band - Custom Songs and ZombieBuddy on every musician.';C.status=C.audioError;return false end
        if U.retrying==song.videoID then
            if call('status')=='ready' and call('resultID')==song.videoID then U.retrying=nil
            else C.audioError=call('status')=='error' and call('error') or 'Retrying custom audio...';C.status=C.audioError;return false end
        end
        local matches=call('matches',song.videoID,song.audioHash,song.chartHash)
        if matches then
            if call('arm',song.videoID) then C.audioError=nil;return true end
            C.audioError=call('error') or 'Preparing audio output...';C.status=C.audioError;return false
        end
        local state=call('status');local requested=call('requestedID')
        if requested~=song.videoID and U.failed~=song.uid then call('begin',song.url);state='downloading' end
        if state=='ready' and call('resultID')==song.videoID then
            U.failed=song.uid;C.audioError='Custom audio/chart differs from the host. Clear this song cache and reload; the band will not start.'
        elseif state=='error' then U.failed=song.uid;C.audioError=call('error') or 'Custom audio preparation failed.'
        else C.audioError='Custom song: '..tostring(state or 'preparing')..'. Waiting for matching audio and chart.' end
        C.status=C.audioError;return false
    end
    local oldPreview=C.previewAudio
    function C.previewAudio(id)
        if B.songs[id] and B.songs[id].videoID then C.status='Custom track preview is unavailable; use PLAY after preparation.';return false end
        return oldPreview(id)
    end
    local oldPlay=UI.play
    function UI:play()
        if U.mode or U.pending then message('Finish loading the custom track, or choose BACK TO LIBRARY before playing a bundled song.');return end
        U.suspended=false
        local song=B.songs[L.selected];if song and song.videoID then U.authorized[song.videoID]=true end
        return oldPlay(self)
    end
    local oldForm=UI.form
    function UI:form()
        if U.mode or U.pending then message('Load the custom track before forming the band.');return end
        U.suspended=false;local song=B.songs[L.selected];if song and song.videoID then U.authorized[song.videoID]=true end
        return oldForm(self)
    end
    local function prepareUpload()
        if not U.pending or U.upload then return end
        local state=call('status')
        if state=='error' then message(call('error') or 'Custom preparation failed.');U.pending=nil;return end
        if state~='ready' or call('resultID')~=U.pending then message('CUSTOM TRACK: '..tostring(state or 'waiting'));return end
        local fields={};for field in (call('manifest',U.pending)..'\t'):gmatch('(.-)\t') do fields[#fields+1]=field end
        local wire={videoID=fields[1],name=fields[2],durationMs=tonumber(fields[3]),audioHash=fields[4],chartHash=fields[5],
            url=fields[6],artist=fields[7],bpm=tonumber(fields[8]) or 0,chart=call('chart',U.pending)}
        if not B.customDescriptor(wire) then message('Downloaded audio has no valid playable chart.');U.pending=nil;return end
        U.upload=wire;U.sentAt=B.now();message('Registering the prepared custom chart with the band server...');C.send('customRegister',wire)
    end
    local function playback()
        local s=C.getSession();local song=s and B.songs[s.song]
        if not song or not song.videoID or (s.phase~='countdown' and s.phase~='playing') or not C.me(s) then clearPlayback();return end
        local token=s.id..':'..s.round
        if U.playing~=token then
            if call('matches',song.videoID,song.audioHash,song.chartHash) and call('schedule',song.videoID,token,-C.elapsed(s)) then U.playing=token
            else C.status=call('error') or 'Custom playback could not start.';return end
        end
        local sound=getSoundManager and getSoundManager();local master=sound and sound.getSoundVolume and sound:getSoundVolume() or 1
        local point=B.point(getPlayer());local gain=B.audioGain(s,point,s.audibleRadius)*master
        -- Stable world-space stereo spread with distance attenuation; AI radius remains server-owned.
        local stereo=math.max(-.8,math.min(.8,(s.x-point.x-(s.y-point.y))/math.max(4,s.audibleRadius)))
        call('update',token,C.elapsed(s),gain,stereo)
        if C.elapsed(s)>=song.durationMs then clearPlayback() end
    end
    local oldTick=C.tick
    function C.tick()
        prepareUpload()
        if U.upload and B.now()-(U.sentAt or 0)>10000 then U.upload=nil;U.pending=nil;message('Custom registration timed out. Retry LOAD URL; no bundled song was started.') end
        oldTick();playback()
    end
    local oldShutdown=C.shutdown
    function C.shutdown() U.cancel();U.mode=false;clearPlayback();return oldShutdown() end
    local oldOpen=C.open
    function C.open(item) U.suspended=false;return oldOpen(item) end
    local oldJoin=UI.join
    function UI:join() U.suspended=false;return oldJoin(self) end
    local oldExit=UI.exitBand
    function UI:exitBand() U.cancel();U.mode=false;clearPlayback();return oldExit(self) end
    local oldCreate=UI.createChildren
    function UI:createChildren()
        oldCreate(self)
        if self.customBtn then return end
        local function button(label,fn)
            local wrapped=function(...) if C.menuCue then C.menuCue('select') end;return fn(...) end
            local b=ISButton:new(0,0,122,26,label,self,wrapped);b:initialise();b:instantiate();self:addChild(b)
            b.sounds=b.sounds or {};b.sounds.activate='ZB_UI_Silent'
            b.backgroundColor={r=.025,g=.09,b=.16,a=1};b.borderColor={r=.12,g=.42,b=.65,a=1}
            return b
        end
        self.customBtn=button('CUSTOM SONG',function()
            U.mode=not U.mode;C.startWhenReady=false;C.stopPreview();self.searchEntry:unfocus();self.playlistName:unfocus()
            if U.mode and self.refreshLocalCustom then self:refreshLocalCustom() end
            if U.mode and self.customURL.focus then self.customURL:focus() elseif not U.mode then self.customURL:unfocus() end
        end)
        self.customURL=ISTextEntryBox:new('',0,0,400,30);self.customURL:initialise();self.customURL:instantiate();self:addChild(self.customURL)
        self.customURL:setPlaceholderText('YouTube URL or local file path (or pick from LOCAL SONGS below)')
        self.customLoad=button('LOAD URL / FILE',function()
            local s=C.getSession();if s and s.host~=C.selfKey() then U.retry() else U.begin(self.customURL:getText()) end
        end)
        self.customCancel=button('CANCEL LOAD',U.cancel)
        self.customBack=button('BACK TO LIBRARY',function() U.cancel();U.mode=false;self.customURL:unfocus() end)
        self.customLocalBox=ISComboBox:new(0,0,360,26,self,nil);self.customLocalBox:initialise();self.customLocalBox:instantiate();self:addChild(self.customLocalBox)
        self.customLocalNames={}
        function self:refreshLocalCustom()
            self.customLocalBox:clear();self.customLocalNames={}
            local list=call('listLocalSongs')
            if type(list)=='string' and list~='' then
                for entry in list:gmatch('[^\r\n]+') do
                    if entry~='' then
                        self.customLocalNames[#self.customLocalNames+1]=entry
                        self.customLocalBox:addOption(entry)
                    end
                end
            end
            if #self.customLocalNames==0 then self.customLocalBox:addOption('Drop .wav/.mp3/.ogg or Clone Hero folder in Zomboid/ZombBand/songs') end
            self.customLocalBox.selected=1
        end
        self.customRefreshBtn=button('REFRESH FILES',function() self:refreshLocalCustom() end)
        self.customLoadLocalBtn=button('LOAD LOCAL',function()
            local picked=self.customLocalNames[self.customLocalBox.selected]
            if picked then U.begin('local:'..picked) else message('Put audio files or Clone Hero folders into Zomboid/ZombBand/songs first.') end
        end)
    end
    local function place(child,x,y,w) child:setX(x);child:setY(y);if w then child:setWidth(w) end end
    local oldDraw=UI.drawMenu
    function UI:drawMenu(s,me)
        oldDraw(self,s,me)
        self.customBtn:setVisible(true);place(self.customBtn,20,76,122)
        self.customBtn:setEnable(not s or s.phase=='lobby')
        for _,child in ipairs({self.customURL,self.customLoad,self.customCancel,self.customBack,self.customLocalBox,self.customRefreshBtn,self.customLoadLocalBtn}) do child:setVisible(U.mode) end
        if not U.mode then return end
        for _,child in pairs(self.children or {}) do
            if child~=self.closeBtn and child~=self.customBtn and child~=self.customURL and child~=self.customLoad and child~=self.customCancel and child~=self.customBack and child~=self.customLocalBox and child~=self.customRefreshBtn and child~=self.customLoadLocalBtn then child:setVisible(false) end
        end
        local w=self.width;self:drawRect(12,102,w-24,self.height-114,.99,.04,.014,.020)
        self:drawRectBorder(12,102,w-24,self.height-114,1,.82,.56,.18)
        self:drawText('ADD CUSTOM SONG  (YOUTUBE  /  LOCAL FILES)',32,122,1,.88,.34,1,UIFont.Large)
        self:drawText('1) Paste a YouTube HTTPS URL or local audio path (.wav/.mp3/.ogg/.flac):',32,160,.90,.82,.72,1,UIFont.Small)
        place(self.customURL,32,184,w-64);place(self.customLoad,32,224,148);place(self.customCancel,190,224,132);place(self.customBack,332,224,166)
        self:drawText('2) Or drop songs / Clone Hero folders inside Zomboid/ZombBand/songs and load here:',32,268,.92,.74,.38,1,UIFont.Small)
        place(self.customLocalBox,32,292,math.max(200,w-380))
        place(self.customLoadLocalBtn,w-334,292,140);place(self.customRefreshBtn,w-184,292,152)
        self.customLoad:setEnable(not U.pending and not U.upload);self.customCancel:setEnable(U.pending~=nil or U.upload~=nil)
        self.customLoadLocalBtn:setEnable(not U.pending and not U.upload and #(self.customLocalNames or {})>0)
        self.customLoad:setTitle(s and s.host~=C.selfKey() and 'RETRY MY AUDIO' or 'LOAD URL / FILE')
        local text=U.message or (backend() and call('toolsStatus') or 'Enable the Custom Songs companion and ZombieBuddy, then restart.')
        -- Wrap long tool/error text rather than running outside the panel.
        local width=math.max(30,math.floor((w-72)/8));local y=342
        text=tostring(text);while #text>0 do self:drawText(text:sub(1,width),32,y,1,.76,.37,1,UIFont.Small);text=text:sub(width+1);y=y+22 end
        for _,line in ipairs({'Local .wav files work out of the box; .mp3/.ogg/.m4a/.flac use ffmpeg (auto-detected if on PATH).',
            'Drop permanent pack tracks cleanly via AGREGAR_CANCIONES.bat -> plays in SP/MP with native 3D audio & previews!',
            'Finite songs between 5s and 8m. Multiplayer checks matching audio/chart hashes before starting.'}) do
            self:drawText(line,32,y+24,.78,.72,.68,1,UIFont.Small);y=y+24
        end
    end
    local oldLayout=UI.layoutPerformance
    function UI:layoutPerformance(active)
        oldLayout(self,active)
        if active then for _,child in ipairs({self.customBtn,self.customURL,self.customLoad,self.customCancel,self.customBack,self.customLocalBox,self.customRefreshBtn,self.customLoadLocalBtn}) do child:setVisible(false) end end
    end
    local oldKey=UI.libraryKey
    function UI:libraryKey(key)
        if U.mode then
            if key==1 then U.cancel();U.mode=false;self.customURL:unfocus()
            elseif key==28 then local s=C.getSession();if s and s.host~=C.selfKey() then U.retry() else U.begin(self.customURL:getText()) end end
            return true
        end
        return oldKey(self,key)
    end
    local oldConsumed=UI.isKeyConsumed
    function UI:isKeyConsumed(key)
        if U.mode and self.customURL:isFocused() then return key==1 or key==28 end
        return oldConsumed(self,key)
    end
end
