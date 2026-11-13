require 'HUNKBand_Shared'
HUNKBandLibrary={}
local L,B=HUNKBandLibrary,HUNKBand
L.categories={'ALL SONGS','FAVORITES','YOUR TRACKS','PLAYED','COMPLETED','UNPLAYED','RECENT','PLAYLIST','LEARNED','EA_H (AYER/HOY)','GREATEST HITS','80s MIXTAPE','90s MIXTAPE','70s / CLASSICAL'}
L.styles={'GUITAR HERO III','ROCK BAND','NOTEBOOK','ARCADE'}
L.sorts={'TITLE','ARTIST','LENGTH','TEMPO','NOTE DENSITY','SOURCE','STARS','GENRE','ALBUM','YEAR','RECENTLY PLAYED','MOST PLAYED','HIGH SCORE','FAVORITES','RECENTLY ADDED'}
L.filter=1;L.sort=1;L.query='';L.selected=1;L.scroll=0;L.rows={};L.revision=0
function L.profile()
    local p=getPlayer()
    if p and p.getModData then
        local data=p:getModData()
        data.ZombBandLibraryV2=data.ZombBandLibraryV2 or {favorites={},records={},attempts={},style=data.ZombBandLibraryV1 and data.ZombBandLibraryV1.style or 1}
        local profile=data.ZombBandLibraryV2
        profile.favorites=profile.favorites or {};profile.records=profile.records or {};profile.attempts=profile.attempts or {};profile.playlists=profile.playlists or {};profile.lastPlayed=profile.lastPlayed or {};profile.style=profile.style or 1
        return profile
    end
    L.temporary=L.temporary or {favorites={},records={},attempts={}}
    return L.temporary
end
function L.catalog(id)
    local song=B.song(id)
    local p=getPlayer and getPlayer() or nil
    -- Do not invent artist, album, year or genre for untagged user recordings.
    return {id=id,title=song.name,artist=song.artist or 'Artist not tagged',
        album=song.album or 'Album not tagged',packKey=song.packKey,requiresMod=song.requiresMod,
        allowed=song.allowedInstruments,allowedLabel=B.allowedInstrumentLabel(song,5),
        learned=p and B.isSongLearned and B.isSongLearned(p,id) or false,
        origin=song.origin or 'imported',source=song.source or 'Supplied track',duration=song.durationMs,bpm=song.bpm,
        genre=song.genre or 'Not tagged',year=song.year or 'Not tagged',added=song.addedAt or id,cover=song.cover or 'media/ui/ZombBand/Library_'..id..'.png'}
end
function L.key(id) return B.songs[id] and (B.songs[id].uid or tostring(id)) or tostring(id) end
function L.resolve(key)
    local indexed=B.songByUid[key];if indexed and B.songs[indexed] and L.key(indexed)==key then return indexed end
    for id in ipairs(B.songs) do if L.key(id)==tostring(key) then return id end end
end
function L.recordKey(id,kind,difficulty) return L.key(id)..':'..tostring(kind or 'acoustic')..':'..tostring(difficulty or 2) end
function L.best(id,kind,difficulty) return L.profile().records[L.recordKey(id,kind,difficulty)] end
function L.isFavorite(id) return L.profile().favorites[L.key(id)]==true end
function L.favorite(id)
    if not B.songs[id] then return end
    local p=L.profile();p.favorites[L.key(id)]=not L.isFavorite(id);L.revision=L.revision+1
end
function L.duration(ms)
    local seconds=math.floor(ms/1000)
    return math.floor(seconds/60)..':'..string.format('%02d',seconds%60)
end
function L.density(id,kind,difficulty) if not B.playable(id,kind or 'acoustic',difficulty or 2) then return 0 end;return #B.notes(id,kind or 'acoustic',difficulty or 2)/math.max(1,B.song(id).durationMs/1000) end
function L.stars(accuracy)
    local stars=0
    for _,threshold in ipairs({60,75,85,93,98}) do if accuracy>=threshold then stars=stars+1 end end
    return stars
end
function L.rebuild(kind,difficulty)
    if B.syncExternalCatalog then pcall(B.syncExternalCatalog) end
    local rows={};local query=string.lower(L.query or '');local profile=L.profile();L.groups={}
    for id=1,#B.songs do
        local rawSong=B.songs[id]
        local avail=not rawSong.requiresMod or B.isSoundAvailable(rawSong)
        local song=L.catalog(id);local best=L.best(id,kind,difficulty)
        local pk=song.packKey
        local category=(L.filter==1 and avail)
            or (L.filter==2 and L.isFavorite(id))
            or (L.filter==3 and (song.origin=='imported' or song.origin=='custom' or song.origin=='user'))
            or (L.filter==4 and (profile.attempts[L.key(id)] or 0)>0)
            or (L.filter==5 and best~=nil)
            or (L.filter==6 and avail and not profile.attempts[L.key(id)])
            or (L.filter==7 and profile.lastPlayed[L.key(id)]~=nil)
            or (L.filter==8 and L.inPlaylist(id))
            or (L.filter==9 and song.learned)
            or (L.filter==10 and pk=='ea_h')
            or (L.filter==11 and pk=='greatest_hits')
            or (L.filter==12 and pk=='g80s')
            or (L.filter==13 and pk=='g90s')
            or (L.filter==14 and (pk=='g70s' or pk=='cmm'))
        local haystack=string.lower(song.title..' '..song.artist..' '..song.album..' '..song.source..' '..(song.allowedLabel or ''))
        if category and (query=='' or haystack:find(query,1,true)) then rows[#rows+1]=song end
    end
    local sort=L.sort
    table.sort(rows,function(a,b)
        local x,y
        if sort==2 then x,y=a.artist:lower(),b.artist:lower()
        elseif sort==3 then x,y=a.duration,b.duration
        elseif sort==4 then x,y=a.bpm,b.bpm
        elseif sort==5 then x,y=L.density(a.id,kind,difficulty),L.density(b.id,kind,difficulty)
        elseif sort==6 then x,y=a.source,b.source
        elseif sort==7 or sort==13 then local aa,bb=L.best(a.id,kind,difficulty),L.best(b.id,kind,difficulty);local k=sort==7 and 'stars' or 'score';x,y=-(aa and aa[k] or 0),-(bb and bb[k] or 0)
        elseif sort==8 then x,y=a.genre,b.genre
        elseif sort==9 then x,y=a.album,b.album
        elseif sort==10 then x,y=tostring(a.year),tostring(b.year)
        elseif sort==11 then x,y=-(profile.lastPlayed[L.key(a.id)] or 0),-(profile.lastPlayed[L.key(b.id)] or 0)
        elseif sort==12 then x,y=-(profile.attempts[L.key(a.id)] or 0),-(profile.attempts[L.key(b.id)] or 0)
        elseif sort==14 then x,y=L.isFavorite(a.id) and 0 or 1,L.isFavorite(b.id) and 0 or 1
        elseif sort==15 then x,y=-a.added,-b.added
        else x,y=a.title:lower(),b.title:lower() end
        if x~=y then return x<y end
        if a.title~=b.title then return a.title:lower()<b.title:lower() end
        return a.id<b.id
    end)
    for _,row in ipairs(rows) do local g=L.groups[row.artist] or {count=0,completed=0};L.groups[row.artist]=g;g.count=g.count+1;if L.best(row.id,kind,difficulty) then g.completed=g.completed+1 end end
    L.rows=rows;local selected=false
    for _,s in ipairs(rows) do if s.id==L.selected then selected=true end end
    if not selected then L.selected=rows[1] and rows[1].id or nil end
    L.scroll=math.max(0,math.min(L.scroll,math.max(0,#rows-(L.pageSize or 6))))
    return rows
end
function L.ensureVisible()
    for i,s in ipairs(L.rows) do if s.id==L.selected then
        if i<=L.scroll then L.scroll=i-1
        elseif i>L.scroll+(L.pageSize or 6) then L.scroll=i-(L.pageSize or 6) end
        break
    end end
end
function L.select(id,C)
    if not B.songs[id] then return false end
    if C and C.stopPreview and L.selected~=id then C.stopPreview();if C.menuCue then C.menuCue('move') end end
    if L.selected~=id and C and C.window then C.window.detailScroll=0 end
    L.selected=id;L.ensureVisible()
    if C then
        local s=C.getSession()
        if not s or s.phase=='lobby' and s.host==C.selfKey() then
            C.song=id
            if C.window then C.window.songBox.selected=id;C.window:chooseSong() end
        end
    end
    return true
end
function L.move(delta,C)
    if #L.rows==0 then return end
    local index=1
    for i,song in ipairs(L.rows) do if song.id==L.selected then index=i;break end end
    index=math.max(1,math.min(#L.rows,index+delta));L.select(L.rows[index].id,C)
end
function L.beginRound(s,me)
    if not me then return end
    local token=s.id..':'..s.round..':'..s.startsAt
    if L.attemptToken==token then return end
    L.attemptToken=token
    local profile=L.profile();local key=L.key(s.song)
    profile.attempts[key]=(profile.attempts[key] or 0)+1;profile.lastPlayed=profile.lastPlayed or {};profile.lastPlayed[key]=B.now();L.revision=L.revision+1
end
function L.finish(s,me)
    if not s or not me then return end
    local token=s.id..':'..s.round..':'..s.startsAt
    if L.finishToken==token then return end
    L.finishToken=token
    local total=#B.notes(s.song,me.kind,me.difficulty)
    local accuracy=math.floor((me.hits or 0)/math.max(1,total)*100+.5)
    local profile=L.profile();local key=L.recordKey(s.song,me.kind,me.difficulty);local best=profile.records[key]
    best=best or {score=0,accuracy=0,stars=0,maxCombo=0}
    profile.records[key]={score=math.max(best.score,me.score or 0),accuracy=math.max(best.accuracy,accuracy),
        stars=math.max(best.stars,L.stars(accuracy)),maxCombo=math.max(best.maxCombo,me.maxCombo or 0)}
    if B.learnSong and getPlayer then B.learnSong(getPlayer(),s.song) end
    if HUNKBandClient and HUNKBandClient.awardPlayProgress then
        HUNKBandClient.awardPlayProgress(s,me,nil,true,accuracy)
    elseif B.addMusicXP and getPlayer and getPlayer() then
        local mult=1+0.25*math.max(0,#(s.members or {})-1)
        B.addMusicXP(getPlayer(),math.max(10,math.floor((me.hits or 0)*0.35+accuracy*0.25))*mult)
    end
    L.revision=L.revision+1
end
-- Local presentation and playlists stay in character modData; shared queues are server-owned.
L.queue={}
function L.style() return L.profile().style or 1 end
function L.cycleStyle() local p=L.profile();p.style=(p.style or 1)%#L.styles+1;L.revision=L.revision+1 end
function L.inPlaylist(id)
    local p=L.profile();for _,v in ipairs(p.playlists and p.playlists[L.playlistName or 'My Setlist'] or {}) do if v==L.key(id) then return true end end
    return false
end
function L.togglePlaylist(id)
    local p=L.profile();p.playlists=p.playlists or {};local name=L.playlistName or 'My Setlist';local list=p.playlists[name] or {};p.playlists[name]=list
    for i,v in ipairs(list) do if v==L.key(id) then table.remove(list,i);L.revision=L.revision+1;return end end
    if #list<100 then list[#list+1]=L.key(id) end;L.revision=L.revision+1
end
function L.savePlaylist(name)
    name=tostring(name or ''):sub(1,32);if name=='' then return false end
    local p=L.profile();p.playlists=p.playlists or {};local stored={};for _,id in ipairs(L.queue) do stored[#stored+1]=L.key(id) end;p.playlists[name]=stored;L.playlistName=name;L.revision=L.revision+1;return true
end
function L.loadPlaylist(name)
    local p=L.profile();local list=p.playlists and p.playlists[name];if not list then return false end
    L.queue={};for _,key in ipairs(list) do local id=L.resolve(key);if id and L.playable(id) then L.queue[#L.queue+1]=id end end
    L.playlistName=name;L.revision=L.revision+1;return true
end
function L.playable(id,kind,difficulty)
    return B.playable(id,kind or 'acoustic',difficulty or 2) and B.isSoundAvailable(B.song(id))
end
function L.part(id,kind,difficulty)
    local song=B.song(id)
    if not B.songAllowsKind(song,kind) then return 'NO INCLUIDO' end
    if not B.isSoundAvailable(song) then return 'MOD: '..tostring(song.requiresMod or 'OFF') end
    if not L.playable(id,kind,difficulty) then return 'NO CHART' end
    local density=L.density(id,kind,difficulty)
    local tag=song.rawCharts and 'STEM RHYTHM' or 'SHARED MIX'
    return string.format('%.1f NPS ',density)..string.rep('*',math.max(1,math.min(5,math.ceil(density))))..' / '..tag
end
function L.completed(kind,difficulty)
    local signature=tostring(L.profile())..':'..L.revision..':'..#B.songs..':'..kind..':'..difficulty
    if L.completedCache and L.completedCache.signature==signature then return L.completedCache.n,L.completedCache.mastered end
    local n,mastered=0,0;for id=1,#B.songs do local r=L.best(id,kind,difficulty);if r then n=n+1;if r.stars==5 then mastered=mastered+1 end end end
    L.completedCache={signature=signature,n=n,mastered=mastered};return n,mastered
end
function L.random(C)
    local s=C and C.getSession and C.getSession()
    if s and s.host~=C.selfKey() then C.status='The band leader selects the track.';return false end
    if s and s.phase~='lobby' and s.phase~='results' then C.status='Choose a random song between performances.';return false end
    local kind=C and C.window and C.window.libraryKind and C.window:libraryKind() or B.instrumentKind(C and C.itemType) or 'acoustic'
    local difficulty=C and C.difficulty or 2
    local available={};local current
    for _,row in ipairs(L.rows) do if L.playable(row.id,kind,difficulty) then
        if row.id==L.selected then current=row.id else available[#available+1]=row.id end
    end end
    if #available==0 then
        if current then if C then C.status='Only one playable song in this collection. Clear search or choose ALL SONGS for more.' end;return L.select(current,C) end
        if C then C.status='No playable songs in this collection. Clear search or change collection.' end;return false
    end
    -- PZ Kahlua omits math.random; ZombRand has an exclusive upper bound.
    local index=ZombRand and ZombRand(#available) or math.floor(B.now())%#available
    local id=available[index+1];L.select(id,C)
    if C then C.status='Random song selected: '..B.song(id).name..'. Press PLAY to begin.' end
    return id
end
function L.addQueue(id) if id and L.playable(id) and #L.queue<100 then L.queue[#L.queue+1]=id;return true end return false end
return L
