require 'HUNKZombBandTestKit_Shared'
HUNKZombBandTestKitServer={}
local S,K=HUNKZombBandTestKitServer,HUNKZombBandTestKit
local lastRequest={}
local function reply(player,data)
    data.protocol=K.protocol
    if isServer() then sendServerCommand(player,K.module,'status',data)
    elseif HUNKZombBandTestKitClient then HUNKZombBandTestKitClient.receive('status',data) end
end
function S.grant(player)
    if isClient() or not player or player:isDead() then return end
    local inventory=player:getInventory()
    if not inventory then return end
    local data=player:getModData()
    data.ZombBandTestKitV1=data.ZombBandTestKitV1 or {items={}}
    local record=data.ZombBandTestKitV1
    record.items=record.items or {}
    local allGranted=true
    for _,fullType in ipairs(K.items) do if not record.items[fullType] then allGranted=false;break end end
    if record.complete and allGranted then reply(player,{complete=true,added=0});return end
    local added,missing=0,{}
    for _,fullType in ipairs(K.items) do
        if not record.items[fullType] then
            local existing=K.find(inventory,fullType)
            if existing then record.items[fullType]=true
            else
                local item=inventory:AddItem(fullType)
                if item then
                    if isServer() then sendAddItemToContainer(inventory,item) end
                    record.items[fullType]=true;added=added+1
                else missing[#missing+1]=fullType end
            end
        end
    end
    record.complete=#missing==0
    reply(player,{complete=record.complete,added=added,missing=missing})
    if added>0 then print('[Zomb-Band Test Kit] supplied '..added..' instruments to '..tostring(player:getOnlineID())) end
end
function S.handle(module,command,player,args)
    if isClient() or module~=K.module or command~='grant' or not player
        or type(args)~='table' or args.protocol~=K.protocol then return end
    local key=tostring(player:getOnlineID())
    local now=getTimestampMs()
    if now-(lastRequest[key] or -10000)<1000 then return end
    lastRequest[key]=now
    -- The authenticated sender is the only recipient; arguments cannot pick a
    -- different character or request arbitrary item types.
    S.grant(player)
end
Events.OnClientCommand.Add(S.handle)
print('[Zomb-Band Test Kit] server loaded - author HUNK')
