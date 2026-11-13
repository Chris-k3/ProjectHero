-- Original custom-track wire model. Audio remains client-local; the server owns charts and admission.
return function(B)
B.baseSongCount=#B.songs;B.customRevision=0
function B.videoID(url)
    if type(url)~='string' or #url>2048 then return nil end
    local host,path=url:match('^https://([^/]+)/(.+)$')
    if not host then return nil end
    host=host:lower();local id
    if host=='youtu.be' then id=path:match('^([%w_-]+)')
    elseif host=='youtube.com' or host=='www.youtube.com' or host=='m.youtube.com' or host=='music.youtube.com' then
        if path:sub(1,6)=='watch?' then id=('&'..path:sub(7)):match('&v=([%w_-]+)')
        else id=path:match('^shorts/([%w_-]+)') or path:match('^embed/([%w_-]+)') end
    end
    if id and #id==11 then return id end
end
local function hash(v) return type(v)=='string' and #v==64 and not v:find('[^0-9a-f]') end
function B.customDescriptor(data)
    if type(data)~='table' or type(data.videoID)~='string' or #data.videoID<8 or #data.videoID>48 or data.videoID:find('[^%w_-]')
        or not hash(data.audioHash) or not hash(data.chartHash) or type(data.name)~='string' or #data.name>480
        or data.name:find('[%c]') or not B.integer(data.durationMs,5000,480000)
        or type(data.chart)~='string' or #data.chart>65000 or #data.chart<3 then return nil end
    local notes={};local last=-1;local length=0
    for t,lane in data.chart:gmatch('(%d+),([1-4])') do
        local ms=tonumber(t);length=length+#t+2
        if #notes>=5000 or ms<2400 or ms>=data.durationMs or ms-last<80 then return nil end
        notes[#notes+1]={ms,tonumber(lane)};last=ms
    end
    if #notes<8 or length+#notes-1~=#data.chart then return nil end
    -- Exact canonical re-encoding rejects partial matches, extra separators and ignored payload text.
    local encoded={};for _,n in ipairs(notes) do encoded[#encoded+1]=n[1]..','..n[2] end
    if table.concat(encoded,';')~=data.chart then return nil end
    local charts={lead={},rhythm={},bass={},drums={},vocals={}}
    for _,role in ipairs({'lead','rhythm','bass','drums','vocals'}) do
        for difficulty=1,4 do
            local part={};local every=({8,4,2,1})[difficulty]
            for i,n in ipairs(notes) do
                local include=(i-1)%every==0
                if role=='vocals' and (i%12>=10) then include=false end
                if include then
                    local lane=n[2]
                    if role=='bass' then lane=(n[2]+1)%4+1
                    elseif role=='rhythm' then lane=(n[2]+(i%2))%4+1
                    elseif role=='vocals' then lane=(n[2]+2)%4+1 end
                    part[#part+1]={n[1],lane}
                end
            end
            if #part==0 then part[1]={notes[1][1],notes[1][2]} end
            charts[role][difficulty]=part
        end
    end
    local isLocal=data.videoID:sub(1,4)=='loc-'
    local url=type(data.url)=='string' and #data.url<=1024 and (data.url:sub(1,6)=='local:' or data.url:sub(1,8)=='https://') and data.url
        or (isLocal and ('local:'..data.videoID) or ('https://www.youtube.com/watch?v='..data.videoID))
    local artist=type(data.artist)=='string' and #data.artist>0 and #data.artist<=120 and data.artist or (isLocal and 'Local song file' or 'Custom YouTube audio')
    local bpm=tonumber(data.bpm) or 0
    return {uid='url-'..data.videoID..'-'..data.audioHash..'-'..data.chartHash,name=data.name,artist=artist,
        source=isLocal and 'Local audio / chart' or 'Prepared URL / automatic attack chart',origin='custom',videoID=data.videoID,url=url,
        audioHash=data.audioHash,chartHash=data.chartHash,wireChart=data.chart,durationMs=data.durationMs,bpm=bpm,
        chartLanes=4,charts=charts,hitSounds=false,sound='ZB_Custom_'..data.audioHash,
        cover='media/ui/ZombBand/Custom.png'}
end
function B.customWire(song,id)
    return {id=id,name=song.name,videoID=song.videoID,url=song.url,artist=song.artist,bpm=song.bpm,audioHash=song.audioHash,chartHash=song.chartHash,durationMs=song.durationMs,chart=song.wireChart}
end
function B.installCustom(data)
    local id=B.integer(data and data.id,B.baseSongCount+1,B.baseSongCount+32)
    local song=B.customDescriptor(data)
    if not song or not id or id>#B.songs+1 then return nil end
    if B.songs[id] then return B.songs[id].uid==song.uid and id or nil end
    B.songs[id]=song;B.songByUid[song.uid]=id;B.customRevision=B.customRevision+1;return id
end
return B
end
