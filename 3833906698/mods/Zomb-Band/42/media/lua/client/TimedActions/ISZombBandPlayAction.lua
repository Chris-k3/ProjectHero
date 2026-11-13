require 'TimedActions/ISBaseTimedAction'
require 'HUNKBand_Shared'
ISZombBandPlayAction=ISBaseTimedAction:derive('ISZombBandPlayAction')
local B=HUNKBand
function ISZombBandPlayAction:session()
    if self.previewSession then
        local live=self.client.getSession()
        if self.client.window and (not live or live.phase=='lobby' or live.phase=='results') and self.client.itemType==self.itemType then return self.previewSession end
        return nil
    end
    local s=self.client.getSession()
    if s and s.id==self.sessionId and s.round==self.round then return s end
end
function ISZombBandPlayAction:isValid()
    local s=self:session()
    return s~=nil and (s.phase=='countdown' or s.phase=='playing')
        and self.client.elapsed(s)<B.song(s.song).durationMs
        and not self.character:isDead() and not self.character:getVehicle()
        and B.hasInstrument(self.character,self.itemType,B.performanceRadius)
end
function ISZombBandPlayAction:start()
    local item,worldObj=B.findInstrument(self.character,self.itemType,B.performanceRadius)
    self.item=item;self.worldObj=worldObj
    if not self.item or not self:isValid() then self:forceStop();return end
    -- Vanilla timed actions synchronize animation and override hand models to
    -- remote observers. Placed world props (DrumKit / MicrophoneStand) stay on stage.
    if self.kind=='violin' then self:setOverrideHandModelsString('Violin','ZombBand_ViolinBow')
    elseif self.kind=='drums' then self:setOverrideHandModelsString('Drumstick','Drumstick')
    elseif self.kind=='vocals' then
        if worldObj then self:setOverrideHandModels(nil,nil)
        elseif self.itemType=='Base.ZombBand_MicrophoneStand' then self:setOverrideHandModelsString('Microphone',nil)
        else self:setOverrideHandModels(self.item,nil) end
    elseif worldObj then
        local model=self.item.getWeaponSprite and self.item:getWeaponSprite() or (self.item.getStaticModel and self.item:getStaticModel())
        if model and model~='' then self:setOverrideHandModelsString(model,nil)
        else self:setOverrideHandModels(nil,nil) end
    else self:setOverrideHandModels(self.item,nil) end
    self:setActionAnim(B.playAnimations[self.kind] or 'ZombBandGuitar')
    self.started=true
end
function ISZombBandPlayAction:update()
    local p=self.character
    if p:getHitReaction()~='' and p:getHitReaction()~=nil or p:isKnockedDown()
        or p:isZombieAttacking() or p:isBumped() then self:forceStop();return end
    if not self:isValid() then self.finishing=true;self:forceComplete() end
end
function ISZombBandPlayAction:stop()
    if HUNKBandCamera then HUNKBandCamera.stop() end
    local s=self:session()
    if self.client.animationAction==self then self.client.animationAction=nil end
    if not self.previewSession and not self.finishing and s and self.client.elapsed(s)<B.song(s.song).durationMs
        and (s.phase=='playing' or s.phase=='countdown') then
        self.client.animationBlocked=s.id..':'..s.round
        self.client.status='Performance interrupted. Join or start a band again when ready.'
        self.client.send('leave',{id=s.id})
    end
    ISBaseTimedAction.stop(self)
end
function ISZombBandPlayAction:perform()
    if HUNKBandCamera then HUNKBandCamera.stop() end
    if self.client.animationAction==self then self.client.animationAction=nil end
    ISBaseTimedAction.perform(self)
end
function ISZombBandPlayAction:new(player,client,session,member)
    local o=ISBaseTimedAction.new(self,player)
    o.client=client;o.sessionId=session.id;o.round=session.round
    o.itemType=member.itemType;o.kind=member.kind;o.maxTime=-1
    o.stopOnWalk=false;o.stopOnRun=true;o.stopOnAim=true
    return o
end
