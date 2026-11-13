require 'TimedActions/ISZombBandPlayAction'
require 'TimedActions/ISTimedActionQueue'
HUNKBandAnimation={}
local A,B=HUNKBandAnimation,HUNKBand
function A.stop(client)
    local action=client.animationAction
    if not action then return end
    client.animationAction=nil;action.finishing=true
    if action.action then action:forceComplete()
    else
        local queue=ISTimedActionQueue.getTimedActionQueue(action.character)
        queue:removeFromQueue(action)
    end
end
function A.update(client,session,member)
    local playing=session and member and B.playAnimations[member.kind]
        and (session.phase=='playing' or session.phase=='countdown')
        and client.elapsed(session)>=0 and client.elapsed(session)<B.song(session.song).durationMs
    local browsing=client.window and (not session or session.phase=='lobby' or session.phase=='results') and not HUNKBandCamera.testUntil
    if browsing and B.hasInstrument(getPlayer(),client.itemType) then
        local p=getPlayer();member={id=B.playerKey(p),kind=B.instrumentKind(client.itemType),itemType=client.itemType,difficulty=client.difficulty,name=p:getUsername()}
        client.browseSession={id='library-'..client.itemType,round=0,phase='playing',song=client.song or 1,startsAt=B.now(),members=session and session.members or {member}}
        session=client.browseSession;playing=true
    else client.browseSession=nil end
    local action=client.animationAction
    if action and (not playing or action.sessionId~=session.id or action.round~=session.round) then
        A.stop(client);action=nil
    end
    if playing and not action and client.animationBlocked~=session.id..':'..session.round then
        local player=getPlayer()
        if not B.findInstrument(player,member.itemType) then return end
        action=ISZombBandPlayAction:new(player,client,session,member)
        action.previewSession=browsing and session or nil
        client.animationAction=action
        ISTimedActionQueue.add(action)
    end
end
