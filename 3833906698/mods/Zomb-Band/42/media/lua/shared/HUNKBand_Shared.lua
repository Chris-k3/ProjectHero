-- Zomb-Band by HUNK. Original Lua rhythm model; see REFERENCES.md.
HUNKBand = HUNKBand or {}
local B = HUNKBand
B.module='HUNKBand'
B.protocol=10
B.maxPlayers=6
B.bandRoomRadius=8
B.joinRadius=12
B.performanceRadius=15
B.noiseIntervalMs=1000
B.floorHeight=3
B.maxRewindMs=500
B.countdownMs=3000
B.aheadMs=175 -- includes the maximum +150 ms player calibration
B.approachMs=2400
B.failureEnabled=true
B.failureGraceMs=5000
B.missDamage={6,8,10,12}
B.songs=require 'HUNKBand_Songs'
local okUserSongs,userSongs=pcall(require,'HUNKBand_UserSongs')
if okUserSongs and type(userSongs)=='table' then
    for _,usong in ipairs(userSongs) do
        if type(usong)=='table' and usong.name then B.songs[#B.songs+1]=usong end
    end
end
local okWorkshop,workshopCatalog=pcall(require,'HUNKBand_WorkshopCatalog')
if okWorkshop and type(workshopCatalog)=='table' and workshopCatalog.appendTo then
    pcall(workshopCatalog.appendTo,B)
end
B.nicheAllowedOverrides={
    ['user-Master_Boot_Record_ANSI_SYS_411d1976']={guitar=true,keyboard=true,bass=true,drums=true},
    ['user-meganeko_Milkshake_0583b822']={keyboard=true,bass=true,drums=true,vocals=true},
    ['user-CHON_Bubble_Dream_55fea586']={guitar=true,acoustic=true,bass=true,drums=true},
    ['user-Molchat_Doma_Sudno_d7b4c3fe']={guitar=true,bass=true,drums=true,vocals=true,keyboard=true},
    ['user-FantomenK_The_Massacre_7c6dbb28']={keyboard=true,guitar=true,bass=true,drums=true},
}
B.songByUid={}
for id,song in ipairs(B.songs) do
    if song.uid then B.songByUid[song.uid]=id end
    if not song.sound then song.sound='ZB_Track_'..id end
    if not song.allowedInstruments and song.uid and B.nicheAllowedOverrides[song.uid] then
        song.allowedInstruments=B.nicheAllowedOverrides[song.uid]
    end
end
B.difficulties={
    {name='Easy',lanes=4,window=190,perfect=90},
    {name='Normal',lanes=4,window=165,perfect=75},
    {name='Hard',lanes=4,window=140,perfect=65},
    {name='Expert',lanes=4,window=115,perfect=55},
}
B.kindOrder={'guitar','acoustic','bass','drums','vocals','keyboard','violin','sax','trumpet','flute','banjo','harmonica'}
B.kindNames={guitar='Electric guitar',acoustic='Acoustic guitar',bass='Bass',
    banjo='Banjo',violin='Violin',flute='Flute',sax='Saxophone',
    trumpet='Trumpet',harmonica='Harmonica',keyboard='Keys',drums='Drums',vocals='Vocals'}
B.soundNames={guitar='Guitar',acoustic='Acoustic',bass='Bass',banjo='Banjo',
    violin='Violin',flute='Flute',sax='Sax',trumpet='Trumpet',
    harmonica='Harmonica',keyboard='Keyboard',drums='Drums',vocals='Vocals'}
B.bandRoles={
    {id='lead',kind='guitar',label='Guitarra Electrica (Lead)'},
    {id='rhythm',kind='acoustic',label='Guitarra Acustica (Rhythm)'},
    {id='bass',kind='bass',label='Bajo Electrico (Bass)'},
    {id='drums',kind='drums',label='Bateria (Drums)'},
    {id='vocals',kind='vocals',label='Microfono / Voz (Vocals)'},
    {id='keyboard',kind='keyboard',label='Teclado / Piano (Keys)'},
    {id='violin',kind='violin',label='Violin (Strings)'},
    {id='sax',kind='sax',label='Saxofon (Brass)'},
    {id='trumpet',kind='trumpet',label='Trompeta (Brass)'},
    {id='flute',kind='flute',label='Flauta (Wind)'},
    {id='banjo',kind='banjo',label='Banjo (Folk)'},
    {id='harmonica',kind='harmonica',label='Armonica (Blues)'},
}
B.roleToKind={lead='guitar',rhythm='acoustic',bass='bass',drums='drums',vocals='vocals',
    guitar='guitar',acoustic='acoustic',banjo='banjo',violin='violin',flute='flute',
    sax='sax',trumpet='trumpet',harmonica='harmonica',keyboard='keyboard'}
B.kindToChartRole={
    guitar='lead',acoustic='rhythm',banjo='rhythm',
    bass='bass',drums='drums',vocals='vocals',
    keyboard='rhythm',violin='lead',sax='lead',
    trumpet='lead',flute='vocals',harmonica='vocals'
}
B.formation={{0,0},{2,0},{-2,0},{1,2},{-1,2},{0,-2}}
B.instrumentOverrides=B.instrumentOverrides or {}
B.playAnimations={guitar='ZombBandGuitar',acoustic='ZombBandGuitar',bass='ZombBandGuitar',
    banjo='ZombBandGuitar',violin='ZombBandViolin',flute='ZombBandFlute',
    harmonica='ZombBandHarmonica',sax='ZombBandSaxophone',trumpet='ZombBandTrumpet',
    keyboard='ZombBandKeytar',drums='ZombBandDrums',vocals='ZombBandVocals'}
B.vanillaInstruments={
    ['Base.GuitarAcoustic']='acoustic', ['Base.Banjo']='banjo',
    ['Base.GuitarElectricBass']='bass', ['Base.GuitarElectric']='guitar',
    ['Base.Flute']='flute', ['Base.Harmonica']='harmonica', ['Base.Keytar']='keyboard',
    ['Base.Saxophone']='sax', ['Base.Trumpet']='trumpet', ['Base.Violin']='violin',
    ['Base.Drumstick']='drums', ['Base.Microphone']='vocals',
    ['Base.ZombBand_ElectricGuitar']='guitar', ['Base.ZombBand_AcousticGuitar']='acoustic',
    ['Base.ZombBand_BassGuitar']='bass', ['Base.ZombBand_DrumKit']='drums',
    ['Base.ZombBand_MicrophoneStand']='vocals',
}
function B.now() return getTimestampMs() end
function B.integer(value,lo,hi)
    local n=tonumber(value)
    if n and n==n and n%1==0 and n>=lo and n<=hi then return n end
    return nil
end
function B.copy(value)
    if type(value)~='table' then return value end
    local result={}
    for k,v in pairs(value) do result[k]=B.copy(v) end
    return result
end
function B.instrumentKind(fullType)
    if type(fullType)~='string' then return nil end
    if fullType=='Base.Hat_Cowboy_Plastic' then return nil end
    local s=string.lower(fullType)
    -- Accessories remain forbidden even if an override incorrectly lists them.
    for _,bad in ipairs({'broken','neck','pick','tuningfork','whistle'}) do
        if s:find(bad,1,true) then return nil end
    end
    if B.kindNames[B.instrumentOverrides[fullType]] then return B.instrumentOverrides[fullType] end
    return B.vanillaInstruments[fullType]
end
function B.ranges(count)
    count=B.integer(count,0,B.maxPlayers) or 0
    if count==0 then return 0,0 end
    return 16+4*(count-1),math.min(12,6+2*(count-1))
end
function B.audioDistance(a,b)
    if not a or not b then return math.huge end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+((a.z-b.z)*B.floorHeight)^2)
end
function B.audioGain(source,listener,radius)
    if not radius or radius<=0 then return 0 end
    local distance=B.audioDistance(source,listener)
    if distance>=radius then return 0 end
    if distance<=2 then return 1 end
    return (1-(distance-2)/(radius-2))^2
end
function B.findInventoryInstrument(player,fullType)
    if not player or not B.instrumentKind(fullType) then return nil end
    for _,item in pairs({player:getPrimaryHandItem(),player:getSecondaryHandItem()}) do
        if item and item:getFullType()==fullType then return item end
    end
    local inv=player:getInventory()
    if not inv then return nil end
    local function contains(container)
        local items=container:getItems()
        for i=0,items:size()-1 do
            local item=items:get(i)
            if item:getFullType()==fullType then return item end
            if instanceof(item,'InventoryContainer') then
                local found=contains(item:getInventory())
                if found then return found end
            end
        end
        return nil
    end
    local ok,found=pcall(contains,inv)
    if ok then return found end
    return nil
end
function B.findWorldInstrument(player,fullType,radius)
    if not player or not B.instrumentKind(fullType) then return nil,nil end
    local cell=getCell and getCell() or (player.getCell and player:getCell())
    if not cell or not cell.getGridSquare then return nil,nil end
    local r=math.ceil(tonumber(radius) or 3.5)
    local px,py,pz=player:getX(),player:getY(),math.floor(player:getZ() or 0)
    local bestItem,bestWorld,bestDist=nil,nil,(tonumber(radius) or 3.5)+0.001
    local function scan()
        for dx=-r,r do
            for dy=-r,r do
                local sq=cell:getGridSquare(math.floor(px)+dx,math.floor(py)+dy,pz)
                local wobjs=sq and sq.getWorldObjects and sq:getWorldObjects()
                if wobjs then
                    for i=0,wobjs:size()-1 do
                        local wobj=wobjs:get(i)
                        local item=wobj and wobj.getItem and wobj:getItem()
                        if item and item:getFullType()==fullType then
                            local wx=(sq:getX() or math.floor(px))+0.5
                            local wy=(sq:getY() or math.floor(py))+0.5
                            local d=math.sqrt((px-wx)^2+(py-wy)^2)
                            if d<=bestDist then bestItem,bestWorld,bestDist=item,wobj,d end
                        end
                    end
                end
            end
        end
    end
    pcall(scan)
    return bestItem,bestWorld
end
function B.findInstrument(player,fullType,radius)
    local invItem=B.findInventoryInstrument(player,fullType)
    if invItem then return invItem,false end
    local worldItem,worldObj=B.findWorldInstrument(player,fullType,radius or 4.0)
    if worldItem then return worldItem,worldObj end
    return nil,nil
end
function B.hasInstrument(player,fullType,radius) return B.findInstrument(player,fullType,radius)~=nil end
function B.song(id) return B.songs[tonumber(id)] or B.songs[1] end
function B.difficulty(id) return B.difficulties[tonumber(id)] or B.difficulties[2] end
function B.resolveSoundName(song)
    if type(song)~='table' then return '' end
    local primary=tostring(song.sound or '')
    if GameSounds and GameSounds.isKnownSound then
        if GameSounds.isKnownSound(primary) then return primary end
        if song.soundAlt and GameSounds.isKnownSound(song.soundAlt) then return song.soundAlt end
    end
    return primary
end
function B.isSoundAvailable(song)
    if type(song)~='table' then return false end
    if song.videoID~=nil then return true end
    if not GameSounds or not GameSounds.isKnownSound then return true end
    return GameSounds.isKnownSound(B.resolveSoundName(song))
end
function B.songAllowsKind(songOrId,kind)
    local song=type(songOrId)=='table' and songOrId or B.songs[tonumber(songOrId) or 0]
    if not song or not kind or not B.kindNames[kind] then return false end
    if type(song.allowedInstruments)~='table' then return true end
    return song.allowedInstruments[kind]==true
end
function B.allowedInstrumentList(songOrId)
    local song=type(songOrId)=='table' and songOrId or B.songs[tonumber(songOrId) or 0]
    local out={}
    for _,k in ipairs(B.kindOrder) do
        if B.songAllowsKind(song,k) then out[#out+1]=k end
    end
    return out
end
function B.allowedInstrumentLabel(songOrId,maxItems)
    local song=type(songOrId)=='table' and songOrId or B.songs[tonumber(songOrId) or 0]
    if not song or type(song.allowedInstruments)~='table' then return 'All instruments' end
    local list=B.allowedInstrumentList(song)
    local names={}
    local cap=tonumber(maxItems) or #list
    for i=1,math.min(#list,cap) do names[#names+1]=B.kindNames[list[i]] or list[i] end
    local text=table.concat(names,', ')
    if #list>cap then text=text..' +'..tostring(#list-cap) end
    return text~='' and text or 'None'
end
function B.chartRole(kind,song)
    local preferred=B.kindToChartRole[kind] or 'lead'
    if song and song.rawCharts then
        if song.rawCharts[kind] and song.rawCharts[kind]~='' then return kind end
        if song.rawCharts[preferred] and song.rawCharts[preferred]~='' then return preferred end
        if song.rawCharts.lead and song.rawCharts.lead~='' then return 'lead' end
    end
    if song and song.charts then
        if song.charts[preferred] then return preferred end
        if (preferred=='rhythm' or preferred=='vocals') and song.charts.lead then return 'lead' end
    end
    return preferred
end
function B.playable(id,kind,difficulty)
    local song=B.songs[tonumber(id)];if not song or not song.sound or not song.durationMs or song.durationMs<=0 then return false end
    if kind and not B.songAllowsKind(song,kind) then return false end
    if song.rawCharts then
        local role=B.chartRole(kind or 'guitar',song)
        local packed=song.rawCharts[role]
        return type(packed)=='string' and #packed>=3
    end
    if song.charts then
        local role=B.chartRole(kind,song)
        local notes=song.charts[role] and song.charts[role][difficulty or 2]
        return type(notes)=='table' and #notes>0
    end
    return song.bars~=nil and song.bpm~=nil -- explicitly generated demo charts
end
local B36={}
do
    local alpha='0123456789abcdefghijklmnopqrstuvwxyz'
    for idx=1,#alpha do B36[string.byte(alpha,idx)]=idx-1 end
end
local charts={}
local function shapeLaneForKind(kind,lane,i,t,prevT,prevLane,lanes)
    local dt=t-(prevT or -1000)
    if kind=='guitar' then
        return lane
    elseif kind=='acoustic' then
        -- Strum chord inversion on rapid consecutive strums
        if dt<290 and i%2==0 then
            local alt=(lane+1)%lanes+1
            return alt~=prevLane and alt or lane
        end
        return lane
    elseif kind=='banjo' then
        -- Rolling Scruggs bluegrass arpeggio cycle across 4 strings
        local roll=({1,3,2,4,3,1,4,2})[((i-1)%8)+1]
        if i%3==0 then return lane end
        return ((roll+lane-2)%lanes)+1
    elseif kind=='bass' then
        -- Anchor root pocket on low lanes (1-2), saving high fills for accents
        if i%5==0 then return lane end
        return ((lane-1)%2)+1+(i%4==0 and 1 or 0)<=lanes and (((lane-1)%2)+1+(i%4==0 and 1 or 0)) or 1
    elseif kind=='drums' then
        -- Kick Pedal (1), Snare (2), Hi-Hat/Rack (3), Crash/Floor (4)
        if lane==1 then return 1 end
        if i%8==0 then return math.min(lanes,4) end
        return lane
    elseif kind=='vocals' then
        -- Smooth stepwise pitch contours without jarring extremes
        if prevLane and math.abs(lane-prevLane)>2 then
            return prevLane+(lane>prevLane and 1 or -1)
        end
        return lane
    elseif kind=='keyboard' then
        -- Flowing ascending/descending piano-roll scale sweeps
        local dir=((math.floor((i-1)/4)%2)==0) and 1 or -1
        if prevLane and dt<420 then return ((prevLane-1+dir)%lanes)+1 end
        return lane
    elseif kind=='violin' then
        -- Bowed S-wave sweep motif
        local wave=({1,2,3,4,3,2})[((i-1)%6)+1]
        if dt<380 then return math.min(lanes,wave) end
        return lane
    elseif kind=='sax' then
        -- Syncopated jazz bend response emphasizing upper horn valves
        if dt<350 and lane==1 then return math.min(lanes,3) end
        if i%4==2 then return ((lane)%lanes)+1 end
        return lane
    elseif kind=='trumpet' then
        -- Bold brass fanfare octaves & stabs
        if lane==2 and i%3==1 then return math.min(lanes,4) end
        return (lane%2==1) and 1 or math.min(lanes,4)
    elseif kind=='flute' then
        -- Airy upper-register wind trills (lanes 2-4, dipping to 1 on breath resets)
        if i%7==1 then return 1 end
        return 2+((lane+i)%math.max(1,lanes-1))
    elseif kind=='harmonica' then
        -- Cross-harp draw/blow groove pairs (1<->2 low harp, 3<->4 bend wail)
        if lane<=2 then return (i%2==0) and 1 or 2 end
        return (i%2==0) and math.min(lanes,3) or math.min(lanes,4)
    end
    return lane
end
local function decodeRawStem(str,maxTier,kind,lanes)
    local notes={}
    local n=#str
    local t=0
    local idx=0
    local prevT,prevLane=-1000,nil
    local pos=1
    while pos+2<=n do
        local b1=string.byte(str,pos)
        local b2=string.byte(str,pos+1)
        local b3=string.byte(str,pos+2)
        pos=pos+3
        local d1,d2,code=B36[b1],B36[b2],B36[b3]
        if d1 and d2 and code then
            t=t+(d1*36+d2)*10
            if code<16 then
                local tier=math.floor(code/4)+1
                if tier<=maxTier then
                    idx=idx+1
                    local baseLane=(code%4)+1
                    local lane=math.max(1,math.min(lanes,shapeLaneForKind(kind,baseLane,idx,t,prevT,prevLane,lanes)))
                    prevT=t;prevLane=lane
                    notes[idx]={index=idx,t=t,lane=lane,durationMs=0}
                end
            end
        end
    end
    return notes
end
function B.notes(songId,kind,difficulty)
    songId=B.integer(songId,1,#B.songs) or 1
    difficulty=B.integer(difficulty,1,#B.difficulties) or 2
    local song,config=B.song(songId),B.difficulty(difficulty)
    local key=(song.uid or tostring(songId))..':'..tostring(kind)..':'..difficulty
    if charts[key] then return charts[key] end
    if song.rawCharts then
        local role=B.chartRole(kind,song)
        local packed=song.rawCharts[role] or ''
        local notes=decodeRawStem(packed,difficulty,kind,config.lanes)
        charts[key]=notes
        return notes
    end
    if song.charts then
        local role=B.chartRole(kind,song)
        local notes={}
        local prevT,prevLane=-1000,nil
        for i,pair in ipairs(song.charts[role][difficulty]) do
            local lane=pair[2]
            if song.chartLanes~=4 then
                if difficulty==1 then lane=(lane-1+math.floor((i-1)/12))%4+1
                elseif difficulty>=3 then lane=math.min(4,1+math.floor((lane-1)*4/5)) end
            end
            lane=math.max(1,math.min(config.lanes,shapeLaneForKind(kind,lane,i,pair[1],prevT,prevLane,config.lanes)))
            prevT=pair[1];prevLane=lane
            notes[i]={index=i,t=pair[1],lane=lane,durationMs=0}
        end
        charts[key]=notes
        return notes
    end
    local seeds={guitar=3,acoustic=4,bass=1,banjo=5,violin=6,flute=7,
        sax=8,trumpet=9,harmonica=10,keyboard=2,drums=11,vocals=12}
    local seed=seeds[kind] or 1
    local notes={}
    local prevT,prevLane=-1000,nil
    -- One bar of audible backing before the first playable note.
    for half=8,song.bars*8-1 do
        local beat=half/2
        local include=half%2==0
        if difficulty==1 then include=half%4==0 end
        if difficulty==3 and half%4==3 then include=true end
        if difficulty==4 then include=true end
        if include then
            local lane=((math.floor(beat/4)*2+math.floor(beat)+half%2+seed+songId)%config.lanes)+1
            if difficulty==1 then lane=(math.floor(beat/2)+seed+songId)%4+1 end
            local i=#notes+1
            local t=math.floor(beat*60000/song.bpm+0.5)
            lane=math.max(1,math.min(config.lanes,shapeLaneForKind(kind,lane,i,t,prevT,prevLane,config.lanes)))
            prevT=t;prevLane=lane
            notes[i]={index=i,t=t,lane=lane,durationMs=0}
        end
    end
    charts[key]=notes
    return notes
end
function B.newPerformance()
    return {score=0,hits=0,misses=0,overhits=0,combo=0,maxCombo=0,judged={},cursor=1,rock=100,failed=false,missRun=0}
end
-- Original recoverable performance meter. The RB3 CrowdRating reference uses
-- weighted note quality, warning/failure thresholds and an initial grace period;
-- this mod uses explicit, readable damage values suited to four tap buttons.
function B.rockEvent(state,judgement,at,difficulty)
    if not B.failureEnabled or state.failed then return end
    local value=state.rock or 100
    if judgement=='miss' then value=value-B.missDamage[difficulty];state.missRun=(state.missRun or 0)+1
    elseif judgement=='overhit' then value=value-4;state.missRun=(state.missRun or 0)+1
    else value=value+(judgement=='perfect' and 3 or 2);state.missRun=0 end
    if at<B.failureGraceMs then value=math.max(1,value) end
    state.rock=math.max(0,math.min(100,value))
    if state.rock<=0 then state.failed=true;state.failedAt=at end
end
-- Long songs need compact network snapshots rather than a large nested table.
function B.packPerformance(state)
    local result={}
    for k,v in pairs(state) do if k~='judged' then result[k]=v end end
    local last=state.cursor-1
    for i in pairs(state.judged) do last=math.max(last,i) end
    local flags={}
    local symbols={perfect='p',good='g',miss='m'}
    for i=1,last do flags[i]=symbols[state.judged[i]] or '-' end
    result.flags=table.concat(flags)
    return result
end
function B.unpackPerformance(state)
    local result={judged={}}
    for k,v in pairs(state) do if k~='flags' then result[k]=v end end
    local names={p='perfect',g='good',m='miss'}
    for i=1,#(state.flags or '') do result.judged[i]=names[state.flags:sub(i,i)] end
    return result
end
function B.multiplier(combo) return math.min(4,1+math.floor(math.max(0,combo-1)/10)) end
function B.expire(state,notes,elapsed,difficulty)
    local count=0
    local window=B.difficulty(difficulty).window
    while notes[state.cursor] and notes[state.cursor].t+window<elapsed do
        local i=state.cursor
        if not state.judged[i] then
            state.judged[i]='miss';state.misses=state.misses+1;state.combo=0;count=count+1
            B.rockEvent(state,'miss',notes[i].t+window,difficulty)
        end
        state.cursor=i+1
        if state.failed then break end
    end
    return count
end
function B.input(state,notes,elapsed,lane,difficulty)
    B.expire(state,notes,elapsed,difficulty)
    local config=B.difficulty(difficulty)
    local best,diff=nil,config.window+1
    for _,note in ipairs(notes) do
        if not state.judged[note.index] and note.lane==lane then
            local delta=math.abs(elapsed-note.t)
            if delta<diff then best=note;diff=delta end
        end
    end
    if best and diff<=config.window then
        local verdict=diff<=config.perfect and 'perfect' or 'good'
        state.judged[best.index]=verdict;state.hits=state.hits+1;state.combo=state.combo+1
        state.maxCombo=math.max(state.maxCombo,state.combo)
        local earned=(verdict=='perfect' and 100 or 60)*B.multiplier(state.combo)
        state.score=state.score+earned
        B.rockEvent(state,verdict,elapsed,difficulty)
        return {judgement=verdict,index=best.index,lane=lane,earned=earned}
    end
    state.combo=0;state.overhits=state.overhits+1
    B.rockEvent(state,'overhit',elapsed,difficulty)
    return {judgement='overhit',lane=lane,earned=0}
end
function B.distance(a,b)
    if not a or not b or math.abs((a.z or 0)-(b.z or 0))>0.1 then return 999 end
    return math.sqrt(((a.x or 0)-(b.x or 0))^2+((a.y or 0)-(b.y or 0))^2)
end
function B.point(p) return {x=p:getX(),y=p:getY(),z=p:getZ()} end
function B.playerKey(p) return p and tostring(p:getOnlineID()) or 'none' end

-- A ready acknowledgment is valid only for this preparation revision/track/part.
function B.preparationStamp(session,member)
    if not session or not member or not B.playable(session.song,member.kind,member.difficulty) then return nil end
    local song=B.song(session.song);local notes=B.notes(session.song,member.kind,member.difficulty)
    if #notes==0 then return nil end
    return table.concat({tostring(session.prepareVersion or 1),song.uid or tostring(session.song),
        tostring(song.durationMs),member.kind,tostring(member.difficulty),tostring(#notes),song.audioHash or 'bundled',song.chartHash or 'bundled'},':')
end

B.musicThresholds={75,150,300,750,1500,3000,4500,6000,7500,9000}
function B.musicSkill(player)
    if Perks and Perks.Music and player and player.getPerkLevel then
        local ok,lvl=pcall(function() return player:getPerkLevel(Perks.Music) end)
        if ok and type(lvl)=='number' then
            local xp=0
            pcall(function() xp=player:getXp():getXP(Perks.Music) end)
            return {level=lvl,xp=xp,native=true}
        end
    end
    if player and player.getModData then
        local md=player:getModData()
        md.ZombBandMusicSkill=md.ZombBandMusicSkill or {level=0,xp=0}
        local rec=md.ZombBandMusicSkill
        rec.level=tonumber(rec.level) or 0
        rec.xp=tonumber(rec.xp) or 0
        return rec
    end
    return {level=0,xp=0}
end
function B.addMusicXP(player,amount)
    amount=tonumber(amount) or 0
    if not player or amount<=0 then return false,0 end
    if Perks and Perks.Music and player.getXp then
        local before=0
        pcall(function() before=player:getPerkLevel(Perks.Music) end)
        pcall(function()
            local xpObj=player:getXp()
            if addXp then addXp(player,Perks.Music,amount)
            elseif xpObj and xpObj.AddXP then xpObj:AddXP(Perks.Music,amount) end
        end)
        local after=before
        pcall(function() after=player:getPerkLevel(Perks.Music) end)
        if Perks.Music then
            local rec=player.getModData and player:getModData()
            if rec then rec.ZombBandMusicSkill={level=after,xp=(rec.ZombBandMusicSkill and rec.ZombBandMusicSkill.xp or 0)+amount} end
            return after>before,after
        end
    end
    local rec=B.musicSkill(player)
    local before=rec.level or 0
    rec.xp=(rec.xp or 0)+amount
    local lvl=0
    local total=0
    for i,req in ipairs(B.musicThresholds) do
        total=total+req
        if rec.xp>=total then lvl=i else break end
    end
    rec.level=math.min(10,lvl)
    return rec.level>before,rec.level
end

B.lifestyleLearnedKeys={
    'GuitarELearnedTracks','GuitarALearnedTracks','GuitarEBLearnedTracks',
    'KeytarLearnedTracks','PianoLearnedTracks','BanjoLearnedTracks',
    'FluteLearnedTracks','SaxophoneLearnedTracks','TrumpetLearnedTracks',
    'ViolinLearnedTracks','HarmonicaLearnedTracks',
}
function B.normalizeSongMatch(s)
    return string.lower(tostring(s or '')):gsub('[^%w]+','')
end
function B.isSongLearned(player,songId)
    local song=type(songId)=='table' and songId or B.songs[tonumber(songId) or 0]
    if not player or not song or not player.getModData then return false end
    local md=player:getModData()
    local zlearned=md and md.ZombBandLearnedV1
    local uid=song.uid or song.sound or song.name
    if zlearned and uid and zlearned[uid]==true then return true end
    local normName=B.normalizeSongMatch(song.name)
    local normFull=B.normalizeSongMatch((song.artist or '')..(song.name or ''))
    local normSound=B.normalizeSongMatch(song.sound)
    for _,lk in ipairs(B.lifestyleLearnedKeys) do
        local tbl=md and md[lk]
        if type(tbl)=='table' then
            for k,v in pairs(tbl) do
                if v==true or type(v)=='table' or type(v)=='string' then
                    local cand=B.normalizeSongMatch(type(k)=='string' and k or (type(v)=='table' and (v.name or v.sound)) or v)
                    if cand~='' and (cand==normName or cand==normFull or cand==normSound) then return true end
                end
            end
        end
    end
    return false
end
function B.learnSong(player,songId)
    local song=type(songId)=='table' and songId or B.songs[tonumber(songId) or 0]
    if not player or not song or not player.getModData then return false end
    local md=player:getModData()
    md.ZombBandLearnedV1=md.ZombBandLearnedV1 or {}
    local uid=song.uid or song.sound or song.name
    if uid and not md.ZombBandLearnedV1[uid] then
        md.ZombBandLearnedV1[uid]=true
        return true
    end
    return false
end
function B.syncExternalCatalog()
    if B.externalSynced or not NMTrackCatalog or type(NMTrackCatalog.entries)~='table' then return 0 end
    B.externalSynced=true
    local knownSounds={}
    for _,s in ipairs(B.songs) do
        if s.sound then knownSounds[tostring(s.sound)]=true end
    end
    local added=0
    for mediaType,entry in pairs(NMTrackCatalog.entries) do
        local tracks=type(entry)=='table' and (entry.tracks or entry) or nil
        if type(tracks)=='table' then
            for _,tr in ipairs(tracks) do
                if type(tr)=='table' and tr.sound and not knownSounds[tostring(tr.sound)] then
                    local rawSnd=tostring(tr.sound)
                    local modPrefix=tostring(mediaType or ''):match('^([^%.]+)%.')
                    local resolvedSnd=rawSnd
                    local avail=true
                    if GameSounds and GameSounds.isKnownSound then
                        if GameSounds.isKnownSound(rawSnd) then resolvedSnd=rawSnd
                        elseif modPrefix and GameSounds.isKnownSound(modPrefix..'.'..rawSnd) then resolvedSnd=modPrefix..'.'..rawSnd
                        else avail=false end
                    end
                    if avail then
                        knownSounds[rawSnd]=true
                        local rawLabel=tostring(tr.label or rawSnd)
                        if getTextOrNull then rawLabel=getTextOrNull(rawLabel) or rawLabel end
                        local artist,title=rawLabel:match('^([^%-]+)%s*%-%s*(.+)$')
                        added=added+1
                        local dur=tonumber(tr.durationMs) or tonumber(tr.lengthMs) or ((tonumber(tr.length) or 180)*1000)
                        local uid='nm-dyn-'..rawSnd
                        local sid=#B.songs+1
                        B.songs[sid]={
                            name=title or rawLabel,
                            artist=artist or (modPrefix or 'New Music'),
                            album=tostring(entry.albumTitle or modPrefix or 'New Music'),
                            uid=uid,
                            sound=resolvedSnd,
                            soundAlt=modPrefix and (modPrefix..'.'..rawSnd) or nil,
                            origin='workshop',
                            requiresMod=modPrefix,
                            source='New Music Pack',
                            genre='Workshop Pack',
                            cover=modPrefix and ('media/ui/ZombBand/Pack_'..modPrefix..'.png') or 'media/ui/ZombBand/GH3_Emblem.png',
                            bpm=120,
                            durationMs=math.max(15000,dur),
                            bars=math.max(8,math.floor(dur/2000)),
                            hitSounds=false,
                            allowedInstruments={guitar=true,acoustic=true,bass=true,drums=true,vocals=true,keyboard=true},
                        }
                        B.songByUid[uid]=sid
                    end
                end
            end
        end
    end
    return added
end

require('HUNKBand_Custom')(B)
