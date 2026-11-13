require 'HUNKZombBandTestKit_Shared'
HUNKZombBandTestKitClient={attempts=0,nextAt=0,done=false}
local C,K=HUNKZombBandTestKitClient,HUNKZombBandTestKit
function C.receive(command,data)
    if command~='status' or type(data)~='table' or data.protocol~=K.protocol then return end
    if data.complete then
        C.done=true
        if HUNKBandClient then HUNKBandClient.status='Test instruments are ready in your inventory.' end
        print('[Zomb-Band Test Kit] ready - look in your inventory for the instruments')
    elseif data.missing and #data.missing>0 then
        print('[Zomb-Band Test Kit] unavailable item types: '..table.concat(data.missing,', '))
    end
end
function C.tick()
    local player=getPlayer()
    if not player or player:isDead() then return end
    if C.player~=player then C.player=player;C.done=false;C.attempts=0;C.nextAt=0 end
    if C.done or getTimestampMs()<C.nextAt then return end
    C.nextAt=getTimestampMs()+2000
    if C.attempts>=6 then
        C.done=true;print('[Zomb-Band Test Kit] request timed out; enable the addon on the server too.');return
    end
    if not isClient() and not HUNKZombBandTestKitServer then return end
    C.attempts=C.attempts+1
    if isClient() then sendClientCommand(player,K.module,'grant',{protocol=K.protocol})
    else HUNKZombBandTestKitServer.grant(player) end
end
Events.OnServerCommand.Add(function(module,command,data) if module==K.module then C.receive(command,data) end end)
Events.OnTick.Add(C.tick)
print('[Zomb-Band Test Kit] client loaded - author HUNK')
