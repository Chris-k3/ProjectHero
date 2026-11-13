return function(S,B,send,broadcast,fail,sync)
    S.customCatalog={}
    function S.customHandle(command,p,args,s,m,limits,now)
        if command=='discover' then
            if args.customRevision~=B.customRevision then
                for _,entry in ipairs(S.customCatalog) do send(p,'customTrack',entry) end
            end
            return false
        end
        if command~='customRegister' then return false end
        if s and (s.host~=B.playerKey(p) or s.phase~='lobby') then fail(p,'Only the band leader can load a custom track in the waiting lobby.');return true end
        if now-(limits.custom or -10000)<2000 then fail(p,'Please wait before loading another custom track.');return true end
        limits.custom=now
        local song=B.customDescriptor(args)
        if not song then fail(p,'Custom track rejected: invalid or missing audio identity / note chart.');return true end
        local id=B.songByUid[song.uid]
        if not id then
            if #S.customCatalog>=32 then fail(p,'This server has reached its 32 custom-track session cache limit. Restart the server to clear it.');return true end
            id=#B.songs+1;local wire=B.customWire(song,id)
            if not B.installCustom(wire) then fail(p,'Unable to register the custom track.');return true end
            S.customCatalog[#S.customCatalog+1]=wire;broadcast('customTrack',wire)
        else send(p,'customTrack',B.customWire(B.song(id),id)) end
        if s then
            s.song=id;s.setlist={};s.prepareVersion=(s.prepareVersion or 1)+1;s.changedAt=now
            for _,member in ipairs(s.members) do member.ready=false;member.readyStamp=nil end
            sync(s)
        end
        return true
    end
end
