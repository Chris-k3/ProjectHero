require 'HUNKBand_Shared'
HUNKBandCamera={enabled=true,focus='band',shotOffset=0,label='Camera companion not loaded'}
local D,B=HUNKBandCamera,HUNKBand
local Z=2.4494895935058594
local shots={
    {name='FULL BAND',distance=4.0,height=1.45,target=0.95,angle=0.30,orbit=0.08,group=true},
    {name='INSTRUMENT',distance=1.35,height=1.10,target=1.08,angle=0.65,orbit=-0.08},
    {name='SIDE PROFILE',distance=2.6,height=1.45,target=1.18,angle=1.45,orbit=0.13},
    {name='LOW ANGLE',distance=2.4,height=0.55,target=1.18,angle=-0.45,orbit=-0.10},
    {name='FACE',distance=1.25,height=1.65,target=1.62,angle=0.25,orbit=0.06},
    {name='OVER SHOULDER',distance=1.8,height=1.65,target=1.15,angle=2.65,orbit=-0.05},
    {name='FULL BODY',distance=3.4,height=1.15,target=0.80,angle=-0.70,orbit=0.10},
    {name='BAND ORBIT',distance=4.2,height=1.65,target=1.05,angle=-1.1,orbit=0.22,group=true},
}
local function lerp(a,b,t) return a+(b-a)*t end
local function point(p) return {x=p:getX(),y=p:getY(),z=p:getZ()} end
local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local function bridge() return ZombBandCamera end
function D.report(message)
    D.label=message
    if D.lastReport~=message and (not D.reportAt or B.now()-D.reportAt>1500) then
        D.lastReport=message;D.reportAt=B.now();print('[Zomb-Band CAMERA] '..message)
    end
end
local function seed(s)
    local h=tonumber(s.round) or 0
    for i=1,#tostring(s.id) do h=(h*31+tostring(s.id):byte(i))%100003 end
    return h
end
function D.players(s)
    local found={};local player=getPlayer()
    if player then found[B.playerKey(player)]=player end
    if getOnlinePlayers then
        local online=getOnlinePlayers()
        if online then for i=0,online:size()-1 do local p=online:get(i);found[B.playerKey(p)]=p end end
    end
    local result={}
    for _,member in ipairs(s.members or {}) do
        local p=found[tostring(member.player or member.key or member.id)]
        if p and not p:isDead() and not p:getVehicle() then
            result[#result+1]={player=p,member=member,point=point(p)}
        end
    end
    return result
end
-- Cache note density once per round. At shot boundaries the director reads a
-- short window of chart activity; it does not rescan every chart each frame.
function D.activity(s,m,elapsed)
    local key=tostring(s.song)..':'..m.kind..':'..m.difficulty
    D.bins=D.bins or {}
    if not D.bins[key] then
        local bins={}
        for _,n in ipairs(B.notes(s.song,m.kind,m.difficulty)) do
            local i=math.floor(n.t/500);bins[i]=(bins[i] or 0)+1
        end
        D.bins[key]=bins
    end
    local bins=D.bins[key];local i=math.floor(math.max(0,elapsed)/500)
    return (bins[i-1] or 0)+(bins[i] or 0)+(bins[i+1] or 0)+(bins[i+2] or 0)
end
local function heading(p)
    if p.getForwardDirection then
        local v=p:getForwardDirection()
        if v then
            local x,y=v:getX(),v:getY()
            if math.abs(x)+math.abs(y)>.01 then return math.atan2(y,x) end
        end
    end
    return -math.pi/2
end
-- Conservative swept checks. Refuse unloaded squares, furniture, closed
-- boundaries, room changes and unsupported floors; never fly through a wall.
function D.clear(a,b,player)
    local function reject(reason) D.blockReason=reason;return false end
    if math.floor(a.z)~=math.floor(b.z) then return reject('different floors') end
    local cell=getCell();if not cell then return false end
    local level=math.floor(a.z)
    local start=cell:getGridSquare(math.floor(a.x),math.floor(a.y),level)
    if not start then return reject('subject square unloaded') end
    local room=start:getRoom();local previous=start
    local count=math.max(1,math.ceil(dist(a,b)/0.12))
    for i=1,count do
        local t=i/count;local x,y=lerp(a.x,b.x,t),lerp(a.y,b.y,t)
        -- A small lens volume, rather than a single infinitely thin ray.
        for _,offset in ipairs({{0,0},{.12,0},{-.12,0},{0,.12},{0,-.12}}) do
            local q=cell:getGridSquare(math.floor(x+offset[1]),math.floor(y+offset[2]),level)
            if not q then return reject('lens square unloaded') end
            if q:getRoom()~=room then return reject('room boundary') end
            if not q:TreatAsSolidFloor() then return reject('no floor beneath lens') end
            -- isFree() also depends on a cached walkability result and actor
            -- occupancy; cameras need actual floor/solid/edge geometry instead.
            if q~=start and (q:isSolid() or q:isSolidTrans()) then return reject('solid object') end
            if q~=previous and previous:testCollideAdjacent(player,q:getX()-previous:getX(),q:getY()-previous:getY(),0) then return reject('wall or closed boundary') end
        end
        previous=cell:getGridSquare(math.floor(x),math.floor(y),level)
    end
    return true
end
local function safe(candidate,target,player)
    return D.clear(target,candidate,player)
end
function D.select(s,people,elapsed,client)
    local bpm=B.song(s.song).bpm or 120;if bpm<=0 then bpm=120 end
    local beat=math.max(0,elapsed)*bpm/60000
    local segment=math.floor(beat/8)
    local index=(segment+seed(s)+D.shotOffset)%#shots+1
    local shot=shots[index]
    local subject=people[(segment+seed(s))%#people+1]
    if D.focus=='self' then
        for _,p in ipairs(people) do if p.player==getPlayer() then subject=p end end
    elseif segment%3==1 then
        local best=-1
        for _,p in ipairs(people) do
            local combo=p.member.combo or 0
            if p.player==getPlayer() then combo=client.state.combo or 0 end
            local value=D.activity(s,p.member,elapsed)+math.min(4,math.floor(combo/20))
            if value>best then subject=p;best=value end
        end
    end
    return shot,subject,segment,beat%8,beat
end
function D.compose(s,people,elapsed,client)
    if #people==0 then return nil end
    local tempo=B.song(s.song).bpm or 120;if tempo<=0 then tempo=120 end
    local beat=math.max(0,elapsed)*tempo/60000
    local segment=math.floor(beat/8);local inShot=beat%8
    local key=tostring(s.id)..':'..s.round..':'..segment..':'..D.focus..':'..D.shotOffset..':'..B.playerKey(getPlayer())
    local plan=D.lastPlan;local subject
    if plan and plan.key==key then
        for _,p in ipairs(people) do if tostring(p.member.id)==plan.subjectId then subject=p;break end end
    end
    if not subject then
        local shot;shot,subject=D.select(s,people,elapsed,client)
        plan={key=key,shot=shot,subjectId=tostring(subject.member.id),heading=heading(subject.player)};D.lastPlan=plan
    end
    -- Direct at shot boundaries. Live chart bins, combo changes and animation
    -- facing must not select a different musician or whip the lens mid-shot.
    local shot=plan.shot
    local target={x=subject.point.x,y=subject.point.y,z=subject.point.z}
    local radius=0
    local group=shot.group and #people>1 and D.focus~='self'
    if group then
        target.x=0;target.y=0
        for _,p in ipairs(people) do
            if math.floor(p.point.z)~=math.floor(target.z) then group=false;break end
            target.x=target.x+p.point.x;target.y=target.y+p.point.y
        end
        if group then
            target.x=target.x/#people;target.y=target.y/#people
            for _,p in ipairs(people) do radius=math.max(radius,dist(target,p.point)) end
        else target=point(subject.player) end
    end
    local angle=plan.heading+shot.angle+shot.orbit*inShot
    -- Keep indoor lenses inside one floor's ceiling/floor envelope.
    local cameraHeight=shot.height;local targetHeight=shot.target
    if shot.name=='INSTRUMENT' then
        local kind=subject.member.kind
        if kind=='flute' or kind=='harmonica' or kind=='trumpet' or kind=='vocals' then targetHeight=1.46
        elseif kind=='violin' then targetHeight=1.35
        elseif kind=='keyboard' then targetHeight=1.00
        elseif kind=='drums' then targetHeight=0.92 end
    end
    local lower=0
    if subject.player.isSitOnGround and subject.player:isSitOnGround() then lower=.90
    elseif subject.player.isSittingOnFurniture and subject.player:isSittingOnFurniture() then lower=.55 end
    cameraHeight=math.max(.35,cameraHeight-lower);targetHeight=math.max(.35,targetHeight-lower)
    local distance=math.min(7,shot.distance+radius*1.4)
    local floorZ=math.floor(subject.point.z)
    target.z=floorZ+targetHeight/Z
    local camera
    local function candidate(turn,scale)
        if distance*scale<1.0 then return nil end
        local c={x=target.x+math.cos(angle+turn)*distance*scale,
                 y=target.y+math.sin(angle+turn)*distance*scale,z=floorZ+cameraHeight/Z}
        if not safe(c,target,subject.player) then return nil end
        if group then for _,p in ipairs(people) do if not D.clear(p.point,c,p.player) then return nil end end end
        return c
    end
    -- Keep the chosen side and distance for the shot, rather than switching
    -- between alternate sides when the orbit grazes an obstacle.
    if plan.turn then camera=candidate(plan.turn,plan.scale) end
    if not camera and plan.turn and D.pose and D.pose.planKey==key then
        local held=D.pose.camera
        local visible=safe(held,target,subject.player)
        if visible and group then for _,p in ipairs(people) do if not D.clear(p.point,held,p.player) then visible=false;break end end end
        if visible then camera=held end
    end
    if not camera then
        -- Prefer another full-distance angle before moving the lens toward the
        -- musician. Very close fallback lenses can intersect held instruments.
        for _,scale in ipairs({1,.85,.7,.55}) do
            for _,turn in ipairs({0,.65,-.65,1.3,-1.3,math.pi}) do
                camera=candidate(turn,scale)
                if camera then plan.turn=turn;plan.scale=scale;break end
            end
            if camera then break end
        end
    end
    if not camera then return nil end
    return {camera=camera,target=target,segment=segment,shot=shot.name,subject=subject.member.name or 'Musician',
        player=subject.player,beat=beat,group=group,planKey=key}
end
function D.restore()
    local api=bridge()
    if api then pcall(function() api.stop() end) end
    if D.player then
        pcall(function() D.player:setBlockMovement(D.previousBlock) end)
        pcall(function() D.player:setIgnoreContextKey(D.previousContext) end)
    end
    D.player=nil;D.pose=nil;D.startedAt=nil;D.native=false;D.lastPlan=nil
end
function D.stop()
    local api=bridge();if api and api.clearPerformer then pcall(function() api.clearPerformer() end) end
    D.restore();D.round=nil;D.lastTick=nil;D.lastPlan=nil;D.people=nil;D.peopleAt=nil;D.testUntil=nil;D.testClient=nil;D.browseStarted=nil
end
function D.toggle() D.enabled=not D.enabled;D.restore() end
function D.toggleFocus() D.focus=D.focus=='band' and 'self' or 'band';D.lastPlan=nil end
function D.nextShot() D.shotOffset=D.shotOffset+1;D.lastPlan=nil end
function D.test(client)
    local s=client.getSession()
    if s and client.isPlaying(s) then client.status='Camera is already running for this performance.';return end
    local api=bridge()
    if not api then client.status='Camera companion not loaded. Enable Zomb-Band - Cinematic Camera and restart.';D.report(client.status);return end
    local p=getPlayer();if not p or p:isDead() or p:getVehicle() then return end
    D.stop();D.enabled=true;D.testUntil=B.now()+6500
    local kind=B.instrumentKind(client.itemType) or 'acoustic'
    local m={id=B.playerKey(p),kind=kind,difficulty=2,name='Camera check'}
    D.testSession={id='camera-check',round=1,phase='playing',song=client.song or 1,startsAt=B.now(),members={m}}
    D.testClient={animationAction={started=true,character=p},state=client.state,window=client.window,
        elapsed=function() return B.now()-D.testSession.startsAt end}
    client.status='Camera check running for 6 seconds. Previous view will be restored.'
end
function D.update(client,s,me)
    if D.testUntil and not D.inTest then
        if s and me and client.elapsed(s)>=0 and (s.phase=='playing' or s.phase=='countdown') then D.stop()
        elseif B.now()>=D.testUntil then D.stop();client.status='Camera check complete. Previous camera and controls restored.';return
        else
            D.inTest=true
            D.update(D.testClient,D.testSession,D.testSession.members[1])
            D.inTest=false
            client.status='CAMERA CHECK / '..D.label
            return
        end
    end
    if not D.inBrowse and not D.inTest and client.browseSession and client.animationAction and not D.testUntil then
        client.performanceEntered=nil
        local band=client.browseSession;local p=getPlayer()
        D.browseStarted=D.browseStarted or B.now()
        local preview={animationAction=client.animationAction,state=client.state,window=client.window,
            elapsed=function() return ((B.now()-D.browseStarted)*.22)%B.song(band.song).durationMs end}
        local member={id=B.playerKey(p),kind=B.instrumentKind(client.itemType),difficulty=client.difficulty,name=p:getUsername()}
        D.inBrowse=true;D.update(preview,band,member);D.inBrowse=false;return
    end
    local action=client.animationAction
    -- Native B42 actions may be queued before their Lua start callback sets a
    -- flag. The shared music clock, membership and valid action own the camera;
    -- a missing started flag must not silently suppress the whole performance.
    local playing=s and me and action and not action.finishing
        and not action.character:isDead() and not action.character:getVehicle()
        and (s.phase=='playing' or s.phase=='countdown')
        and client.elapsed(s)>=0 and client.elapsed(s)<B.song(s.song).durationMs
        and client.animationBlocked~=s.id..':'..s.round
    if not playing then
        if D.round then D.stop() end
        if client.performanceEntered then
            client.performanceEntered=nil
            local completed=s and me and (s.phase=='results' or client.elapsed(s)>=B.song(s.song).durationMs-100)
            if completed then client.status='Performance complete. Choose another track and press PLAY SELECTED.'
            elseif client.window then client.window:removeFromUIManager();client.window=nil end
        end
        return
    end
    client.performanceEntered=true
    local key=s.id..':'..s.round
    if D.round~=key then
        D.restore();D.lastTick=nil;D.people=nil;D.peopleAt=nil;D.round=key;D.shotOffset=0
    end
    local api=bridge()
    if api and api.setPerformer then api.setPerformer(getPlayer()) end
    if not D.enabled then D.report('CAMERA OFF');return end
    if not api then D.report('Camera companion not loaded - enable it and restart');return end
    local now=B.now()
    if D.lastTick and now-D.lastTick<33 then return end
    local dt=D.lastTick and math.min(.1,math.max(0,(now-D.lastTick)/1000)) or .033;D.lastTick=now
    local ok,err=pcall(function()
        if not api.available() then D.report(api.error());D.restore();return end
        if not D.peopleAt or now-D.peopleAt>250 then D.people=D.players(s);D.peopleAt=now end
        for _,p in ipairs(D.people) do
            p.point=point(p.player)
            if api.protectPerformer then api.protectPerformer(p.player) end
        end
        local pose=D.compose(s,D.people,client.elapsed(s),client)
        if not pose then D.restore();D.report('Normal camera: '..tostring(D.blockReason or 'no loaded band subjects'));return end
        local previous=D.pose;local cut=true
        if previous and previous.planKey==pose.planKey and previous.player==pose.player then
            local alpha=1-math.exp(-dt*5)
            local c={x=lerp(previous.camera.x,pose.camera.x,alpha),y=lerp(previous.camera.y,pose.camera.y,alpha),z=lerp(previous.camera.z,pose.camera.z,alpha)}
            -- Interpolation gets its own swept test. A blocked move becomes a
            -- deliberate cut; it never slides through an obstacle.
            if D.clear(previous.camera,c,pose.player) and safe(c,pose.target,pose.player) then
                cut=false
                pose.camera=c
                pose.target={x=lerp(previous.target.x,pose.target.x,alpha),y=lerp(previous.target.y,pose.target.y,alpha),z=lerp(previous.target.z,pose.target.z,alpha)}
            end
        end
        if not D.player then
            D.player=getPlayer();D.previousBlock=D.player:isBlockMovement();D.previousContext=D.player:isIgnoreContextKey()
            api.lockControls(D.player)
            D.player:setBlockMovement(true);D.player:setIgnoreContextKey(true)
        end
        local c,t=pose.camera,pose.target
        if not api.setPose(c.x,c.y,c.z,t.x,t.y,t.z,cut) then D.restore();D.report('Camera unavailable: '..tostring(api.error()));return end
        D.native=true;D.pose=pose;D.report(pose.shot..' / '..pose.subject)
        D.startedAt=D.startedAt or now
        if now-D.startedAt>1800 and api.frames()==0 then
            D.restore();D.report('Camera hook received poses but drew no frames - restart the game');D.lastTick=now+3000
        end
    end)
    if not ok then D.restore();D.report('Camera retry: '..tostring(err));D.lastTick=now+3000 end
end
return D
