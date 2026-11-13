require 'HUNKBand_Shared'
HUNKBandServer=HUNKBandServer or {}
local S,B=HUNKBandServer,HUNKBand
S.sessions={}
S.counter=0
local connections={}
local function players()
    local result={}
    if isServer() then
        local list=getOnlinePlayers()
        if list then for i=0,list:size()-1 do local p=list:get(i);result[B.playerKey(p)]=p end end
    else
        local p=getPlayer()
        if p then result[B.playerKey(p)]=p end
    end
    return result
end
local function send(player,command,data)
    data.protocol=B.protocol
    if isServer() then sendServerCommand(player,B.module,command,data)
    elseif HUNKBandClient then HUNKBandClient.receive(command,B.copy(data)) end
end
local function broadcast(command,data)
    for _,p in pairs(players()) do send(p,command,data) end
end
local function fail(p,message) send(p,'error',{message=message}) end
local function member(s,key)
    for _,m in ipairs(s.members) do if m.id==key then return m end end
end
local function sessionFor(key)
    for _,s in pairs(S.sessions) do local m=member(s,key);if m then return s,m end end
end
local function snapshot(s)
    local audibleRadius,zombieRadius=B.ranges(#s.members)
    local data={id=s.id,host=s.host,x=s.x,y=s.y,z=s.z,song=s.song,
        phase=s.phase,startsAt=s.startsAt,round=s.round,prepareVersion=s.prepareVersion or 1,members={},setlist=B.copy(s.setlist or {}),
        audibleRadius=audibleRadius,zombieRadius=zombieRadius}
    for _,m in ipairs(s.members) do
        data.members[#data.members+1]={id=m.id,name=m.name,kind=m.kind,itemType=m.itemType,difficulty=m.difficulty,
            slot=m.slot,x=m.x,y=m.y,z=m.z,ready=m.ready,readyStamp=m.readyStamp,score=m.state.score,
            hits=m.state.hits,misses=m.state.misses,maxCombo=m.state.maxCombo,combo=m.state.combo}
    end
    return data
end
local function sync(s) broadcast('sync',snapshot(s)) end
local function remove(s)
    S.sessions[s.id]=nil
    broadcast('remove',{id=s.id})
end
local function reassign(s)
    if #s.members==0 then remove(s);return end
    if not member(s,s.host) then s.host=s.members[1].id end
    for i,m in ipairs(s.members) do
        m.slot=i
        local xy=B.formation[i]
        m.x,m.y,m.z=math.floor(s.x+xy[1]),math.floor(s.y+xy[2]),s.z
    end
    sync(s)
end
local function usable(p,item)
    return not p:isDead() and not p:getVehicle() and B.hasInstrument(p,item,B.performanceRadius)
end
local function resolveKind(item,role)
    local itemKind=B.instrumentKind(item)
    local mapped=role and B.roleToKind and B.roleToKind[tostring(role)]
    if mapped and B.kindNames[mapped] then
        if itemKind and itemKind~=mapped and not B.roleOverrideAllowed then
            -- Allow switching role within the same item only when no strict role mismatch exists;
            -- otherwise require holding an instrument matching the requested band role.
            local sameFamily=((itemKind=='guitar' or itemKind=='acoustic') and (mapped=='guitar' or mapped=='acoustic'))
            if not sameFamily then return itemKind end
        end
        return mapped
    end
    return itemKind
end
local function songInstrumentError(songId,kind)
    local song=B.song(songId)
    if B.songAllowsKind(song,kind) then return nil end
    return 'Solo instrumentos de "'..tostring(song.name)..'": '..B.allowedInstrumentLabel(song)
end
local function failMember(s,m,p)
    if not m.state.failed then return false end
    send(p,'failed',{id=s.id,round=s.round,score=m.state.score,misses=m.state.misses,overhits=m.state.overhits})
    for i=#s.members,1,-1 do if s.members[i]==m then table.remove(s.members,i);break end end
    reassign(s)
    return true
end
local function add(s,p,item,difficulty,role)
    local slot=#s.members+1
    local xy=B.formation[slot]
    s.members[slot]={id=B.playerKey(p),name=tostring(p:getUsername() or 'Survivor'),
        kind=resolveKind(item,role),itemType=item,difficulty=difficulty,slot=slot,
        x=math.floor(s.x+xy[1]),y=math.floor(s.y+xy[2]),z=s.z,
        state=B.newPerformance(),seq=0,lastInput=-100000,ready=false}
end
local function stateTo(s,m,p,verdict)
    send(p,'state',{id=s.id,round=s.round,seq=m.seq,state=B.packPerformance(m.state),verdict=verdict})
end
local function invalidatePreparation(s)
    s.prepareVersion=(s.prepareVersion or 1)+1
    for _,m in ipairs(s.members) do m.ready=false;m.readyStamp=nil end
end
local function start(s,p)
    local live=players()
    for _,m in ipairs(s.members) do
        local other=live[m.id]
        if not other or not usable(other,m.itemType) or B.distance(B.point(other),s)>B.performanceRadius then
            fail(p,'Every band member must be nearby, alive, on foot, and carrying their instrument.');return
        end
        local instErr=songInstrumentError(s.song,m.kind)
        if instErr then fail(p,tostring(m.name)..': '..instErr);return end
        if not B.playable(s.song,m.kind,m.difficulty) then fail(p,'A selected instrument has no chart.');return end
        if not m.ready or m.readyStamp~=B.preparationStamp(s,m) then fail(p,'Waiting for every player to prepare this track and chart.');return end
    end
    s.round=s.round+1;s.phase='countdown';s.startsAt=B.now()+(B.countdownMs or 3000)
    s.nextNoiseAt=s.startsAt
    for _,m in ipairs(s.members) do
        m.state=B.newPerformance();m.seq=0;m.lastInput=-100000;m.lastPacket=nil
        m.notes=B.notes(s.song,m.kind,m.difficulty)
    end
    s.changedAt=B.now()
    sync(s)
end
require('HUNKBand_CustomServer')(S,B,send,broadcast,fail,sync)
function S.handle(command,p,args)
    if isClient() then return end
    if not p or type(args)~='table' then return end
    if args.protocol~=B.protocol then fail(p,'Zomb-Band version mismatch. Install v0.10.0 on every client and server.');return end
    local now,key=B.now(),B.playerKey(p)
    local s,m=sessionFor(key)
    local limits=connections[key] or {};connections[key]=limits
    if command~='discover' and S.customHandle(command,p,args,s,m,limits,now) then return end
    if command=='ping' then
        if now-(limits.ping or -10000)<100 then return end
        limits.ping=now
        send(p,'pong',{nonce=args.nonce,serverAt=now})
        return
    elseif command=='discover' then
        if now-(limits.discover or -10000)<500 then return end
        limits.discover=now
        S.customHandle(command,p,args,s,m,limits,now)
        local list={}
        for _,other in pairs(S.sessions) do
            if member(other,key) or (other.phase=='lobby' and B.distance(B.point(p),other)<=B.joinRadius) then
                list[#list+1]=snapshot(other)
            end
        end
        send(p,'sessions',{sessions=list})
        if s then stateTo(s,m,p) end
        return
    elseif command=='create' then
        if s then sync(s);return end
        local song=B.integer(args.song,1,#B.songs)
        local diff=B.integer(args.difficulty,1,#B.difficulties)
        local item=tostring(args.itemType or '')
        local kind=resolveKind(item,args.role)
        if not song or not diff or not B.instrumentKind(item) or not usable(p,item) then fail(p,'Choose a song and difficulty, and carry or stand near a usable instrument while on foot.');return end
        local instErr=songInstrumentError(song,kind)
        if instErr then fail(p,instErr);return end
        if not B.playable(song,kind,diff) then fail(p,'Selected song has no playable chart for '..tostring(B.kindNames[kind] or kind)..'.');return end
        S.counter=S.counter+1
        s={id=tostring(now)..'_'..S.counter,host=key,x=p:getX(),y=p:getY(),z=p:getZ(),
            song=song,phase='lobby',startsAt=0,round=0,prepareVersion=1,members={},changedAt=now}
        add(s,p,item,diff,args.role);S.sessions[s.id]=s;sync(s)
        return
    elseif command=='join' then
        if s then fail(p,'Leave your current band before joining another.');return end
        s=S.sessions[tostring(args.id or '')]
        local diff=B.integer(args.difficulty,1,#B.difficulties)
        local item=tostring(args.itemType or '')
        if not s or s.phase~='lobby' or #s.members>=B.maxPlayers then fail(p,'That band is full or has already started.');return end
        if not diff or not B.instrumentKind(item) or not usable(p,item) or B.distance(B.point(p),s)>B.joinRadius then fail(p,'Carry or stand near an instrument within range of the band on the same floor.');return end
        local kind=resolveKind(item,args.role)
        local instErr=songInstrumentError(s.song,kind)
        if instErr then fail(p,instErr);return end
        add(s,p,item,diff,args.role);s.changedAt=now;sync(s);return
    end
    if not s then return end
    if args.id and tostring(args.id)~=s.id then return end
    if command=='leave' then
        for i,other in ipairs(s.members) do if other.id==key then table.remove(s.members,i);break end end
        reassign(s);return
    elseif command=='setlist' and s.phase=='lobby' and s.host==key then
        if type(args.songs)~='table' or #args.songs>100 then fail(p,'Setlists support up to 100 charted songs.');return end
        local list={}
        for _,id in ipairs(args.songs) do
            id=B.integer(id,1,#B.songs)
            if not id or not B.playable(id,m.kind,m.difficulty) then fail(p,'That song has no playable chart.');return end
            list[#list+1]=id
        end
        s.setlist=list;sync(s);return
    elseif command=='instrument' and (s.phase=='lobby' or s.phase=='results') then
        local item=tostring(args.itemType or m.itemType or '')
        if not B.instrumentKind(item) or not usable(p,item) then fail(p,'Carry or stand near the selected instrument.');return end
        local nextKind=resolveKind(item,args.role)
        local instErr=songInstrumentError(s.song,nextKind)
        if instErr then fail(p,instErr);return end
        m.itemType=item;m.kind=nextKind;invalidatePreparation(s);sync(s);return
    elseif command=='advance' and s.phase=='results' and s.host==key and #(s.setlist or {})>0 then
        s.song=table.remove(s.setlist,1);s.phase='lobby';s.startsAt=0;s.changedAt=now
        invalidatePreparation(s)
        sync(s);return
    elseif command=='unready' and s.phase=='lobby' then
        if m.ready then m.ready=false;m.readyStamp=nil;sync(s) end
        return
    elseif command=='ready' and s.phase=='lobby' then
        local expected=B.preparationStamp(s,m)
        if not expected or args.stamp~=expected then return end
        m.ready=true;m.readyStamp=args.stamp;sync(s);return
    elseif command=='difficulty' and s.phase=='lobby' then
        local diff=B.integer(args.difficulty,1,#B.difficulties)
        if diff and diff~=m.difficulty then m.difficulty=diff;s.changedAt=now;invalidatePreparation(s);sync(s) end
    elseif command=='song' and s.phase=='lobby' and s.host==key then
        local song=B.integer(args.song,1,#B.songs)
        if song and song~=s.song and B.playable(song,m.kind,m.difficulty) then
            s.setlist={};s.song=song;s.changedAt=now
            invalidatePreparation(s)
            sync(s)
        end
    elseif command=='start' and s.phase=='lobby' and s.host==key then start(s,p)
    elseif command=='replay' and s.phase=='results' and s.host==key then
        s.phase='lobby';s.startsAt=0;s.changedAt=now;invalidatePreparation(s);sync(s)
    elseif command=='input' then
        if (s.phase~='countdown' and s.phase~='playing') or args.round~=s.round then return end
        local seq=B.integer(args.seq,1,1000000)
        if not seq or seq<=m.seq then return end
        -- Ordered reliable commands; a sequence gap must not replay old inputs.
        m.seq=seq
        local lane=B.integer(args.lane,1,B.difficulty(m.difficulty).lanes)
        local at=tonumber(args.at)
        local elapsed=now-s.startsAt
        local valid=lane and at and at==at and at>=0 and at>=m.lastInput
            and at<=elapsed+B.aheadMs and at>=elapsed-B.maxRewindMs
            and at<=B.song(s.song).durationMs+B.difficulty(m.difficulty).window
            and usable(p,m.itemType) and B.distance(B.point(p),s)<=B.performanceRadius
        if not valid or now-(m.lastPacket or -10000)<12 then
            stateTo(s,m,p,{judgement='rejected'});return
        end
        m.lastPacket=now;m.lastInput=at
        local verdict=B.input(m.state,m.notes,at,lane,m.difficulty)
        stateTo(s,m,p,verdict)
        if failMember(s,m,p) then return end
        if verdict.index and B.song(s.song).hitSounds~=false then
            local data={id=s.id,round=s.round,player=key,kind=m.kind,lane=lane,seq=seq,
                x=p:getX(),y=p:getY(),z=p:getZ()}
            broadcast('note',data)
        end
    end
end
local lastUpdate=0
function S.update()
    if isClient() then return end
    local now=B.now()
    if now-lastUpdate<50 then return end
    lastUpdate=now
    local live=players()
    for _,s in pairs(S.sessions) do
        local changed=false
        for i=#s.members,1,-1 do
            local m=s.members[i]
            local p=live[m.id]
            local performing=s.phase=='countdown' or s.phase=='playing'
            local invalid=not p or p:isDead()
            if not invalid and performing then
                invalid=not usable(p,m.itemType) or B.distance(B.point(p),s)>B.performanceRadius
            end
            if invalid then table.remove(s.members,i);changed=true end
        end
        if changed then reassign(s) end
        if S.sessions[s.id] then
            if s.phase=='lobby' and now-s.changedAt>600000 then remove(s)
            elseif s.phase=='countdown' and now>=s.startsAt then s.phase='playing';sync(s) end
            if s.phase=='playing' then
                local elapsed=now-s.startsAt
                for i=#s.members,1,-1 do
                    local m=s.members[i]
                    if B.expire(m.state,m.notes,elapsed-B.maxRewindMs,m.difficulty)>0 then stateTo(s,m,live[m.id]) end
                    failMember(s,m,live[m.id])
                end
                -- One AI world-sound pulse per BAND, only while audio is active.
                -- Clients never attract zombies, and musical misses do not mute a mix.
                if S.sessions[s.id] and elapsed>=0 and elapsed<B.song(s.song).durationMs and now>=(s.nextNoiseAt or 0) then
                    local _,radius=B.ranges(#s.members)
                    addSound(live[s.host],math.floor(s.x),math.floor(s.y),math.floor(s.z),radius,radius)
                    s.nextNoiseAt=now+B.noiseIntervalMs
                end
                if S.sessions[s.id] and elapsed>=B.song(s.song).durationMs+B.maxRewindMs+250 then
                    for _,m in ipairs(s.members) do
                        B.expire(m.state,m.notes,math.huge,m.difficulty)
                        stateTo(s,m,live[m.id])
                    end
                    s.phase='results';s.changedAt=now;sync(s)
                end
            elseif s.phase=='results' and now-s.changedAt>120000 then remove(s) end
        end
    end
    for key in pairs(connections) do if not live[key] then connections[key]=nil end end
end
function S.onClientCommand(module,command,p,args)
    if module==B.module then S.handle(command,p,args) end
end
Events.OnClientCommand.Add(S.onClientCommand)
Events.OnTick.Add(S.update)
print('[Zomb-Band] v0.10.0 server loaded - author HUNK')

