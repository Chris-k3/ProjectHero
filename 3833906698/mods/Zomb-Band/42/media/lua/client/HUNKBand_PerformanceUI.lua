-- Fixed screen-space Guitar Hero III style rhythm overlay & per-instrument falling modes.
-- World camera changes never affect hit timing.
return function(UI,C,B,D)
    local colors={
        {.16,.92,.32}, -- 1: Green
        {.98,.20,.23}, -- 2: Red
        {1.0,.84,.16}, -- 3: Yellow
        {.20,.56,1.0}, -- 4: Blue
        {1.0,.48,.12}, -- 5: Orange
    }
    local texCache={}
    local function getTex(path)
        if not path then return nil end
        local cached=texCache[path]
        if cached==false then return nil end
        if cached then return cached end
        if getTexture then
            local ok,t=pcall(getTexture,path)
            if ok and t then texCache[path]=t;return t end
        end
        texCache[path]=false
        return nil
    end

    local function drawSeg(self,x1,y1,x2,y2,a,r,g,b)
        if self.drawLine2 then
            self:drawLine2(x1,y1,x2,y2,a,r,g,b)
        else
            local mx,my=(x1+x2)*.5,(y1+y2)*.5
            self:drawRect(mx-1,my-1,2,2,a,r,g,b)
        end
    end

    local function formatScore(n)
        local s=tostring(math.floor(math.max(0,n or 0)))
        local len=#s
        if len<=3 then return s end
        local out={}
        for i=1,len do
            local rem=len-i+1
            out[#out+1]=s:sub(i,i)
            if rem>1 and (rem-1)%3==0 then out[#out+1]=',' end
        end
        return table.concat(out)
    end

    -- Per-instrument highway visual profiles
    local function profileForKind(kind)
        if kind=='guitar' then
            return {mode='perspective',label='LEAD FRETBOARD',topRatio=.44,exp=1.32,
                bg={.03,.025,.035},rail={.82,.64,.22},fret={.55,.52,.48},
                noteTex='media/ui/ZombBand/GH3_Gem_',directGems=true}
        elseif kind=='acoustic' then
            return {mode='acoustic',label='ACOUSTIC NECK',topRatio=.50,exp=1.22,
                bg={.10,.05,.03},rail={.85,.68,.38},fret={.76,.62,.40},
                noteTex='media/ui/ZombBand/GH3_Note_Pick.png',sway=14}
        elseif kind=='banjo' then
            return {mode='banjo',label='BANJO ROLLS',topRatio=.48,exp=1.18,
                bg={.13,.11,.075},rail={.92,.76,.28},fret={.82,.74,.52},
                noteTex='media/ui/ZombBand/GH3_Note_Pick.png',sway=8}
        elseif kind=='bass' then
            return {mode='bass',label='BASS GROOVE',topRatio=.54,exp=1.42,
                bg={.025,.04,.08},rail={.35,.68,.95},fret={.38,.50,.66},
                noteTex=nil,heavy=true}
        elseif kind=='drums' then
            return {mode='drums',label='DRUM KIT + KICK',topRatio=.58,exp=1.28,
                bg={.05,.045,.055},rail={.96,.46,.16},fret={.48,.46,.52},
                noteTex='media/ui/ZombBand/GH3_Note_Pad.png',kickBar=true}
        elseif kind=='vocals' then
            return {mode='horizontal',label='VOCAL PITCH RIBBON',topRatio=1.0,exp=1.0,
                bg={.06,.03,.08},rail={.90,.35,.72},fret={.58,.32,.56},
                noteTex='media/ui/ZombBand/GH3_Note_Vocal.png'}
        elseif kind=='keyboard' then
            return {mode='pianoroll',label='PIANO CASCADE',topRatio=1.0,exp=1.0,
                bg={.035,.04,.06},rail={.30,.84,.98},fret={.22,.36,.44},
                noteTex='media/ui/ZombBand/GH3_Note_Key.png'}
        elseif kind=='violin' then
            return {mode='wave',label='BOW RIBBON STAVE',topRatio=.56,exp=1.12,
                bg={.11,.035,.04},rail={.94,.72,.28},fret={.65,.42,.26},
                noteTex='media/ui/ZombBand/GH3_Note_Notehead.png',waveAmp=30}
        elseif kind=='sax' or kind=='trumpet' then
            return {mode='fan',label=kind=='sax' and 'BRASS BELL FAN' or 'TRUMPET FANFARE',topRatio=.18,exp=1.35,
                bg={.07,.05,.02},rail=kind=='sax' and {.96,.72,.22} or {.96,.88,.55},fret={.66,.54,.24},
                noteTex='media/ui/ZombBand/GH3_Note_Valve.png'}
        elseif kind=='flute' or kind=='harmonica' then
            return {mode='rising',label=kind=='flute' and 'RISING WIND STREAM' or 'RISING HARP REEDS',topRatio=.66,exp=1.12,
                bg=kind=='flute' and {.02,.07,.09} or {.09,.045,.025},
                rail=kind=='flute' and {.42,.92,.96} or {.96,.62,.24},
                fret={.42,.56,.58},
                noteTex='media/ui/ZombBand/GH3_Note_Arrow.png'}
        end
        return {mode='perspective',label='LEAD FRETBOARD',topRatio=.44,exp=1.32,
            bg={.03,.025,.035},rail={.82,.64,.22},fret={.55,.52,.48},
            noteTex='media/ui/ZombBand/GH3_Gem_',directGems=true}
    end

    function UI:layoutPerformance(active)
        local width,height=getCore():getScreenWidth(),getCore():getScreenHeight()
        local signature=tostring(active)..':'..width..':'..height..':'..tostring(C.hudCentered)
        if self.layoutSignature==signature then return end
        self.layoutSignature=signature;self.moveWithMouse=not active
        if active then
            self:setX(0);self:setY(0);self:setWidth(width);self:setHeight(height)
            self.closeBtn:setX(width-44);self.closeBtn:setY(12)
            self.leaveBtn:setX(width-140);self.leaveBtn:setY(height-40)
            self.cameraBtn:setX(16);self.cameraBtn:setY(height-40)
            self.focusBtn:setX(158);self.focusBtn:setY(height-40)
            self.cutBtn:setX(300);self.cutBtn:setY(height-40)
            if self.hudPosBtn then self.hudPosBtn:setX(412);self.hudPosBtn:setY(height-40) end
            self:bringToTop()
        else
            self:setWidth(760);self:setHeight(600)
            self:setX(math.max(0,(width-760)/2));self:setY(math.max(0,(height-600)/2))
            self.closeBtn:setX(716);self.closeBtn:setY(14)
            self.leaveBtn:setX(610);self.leaveBtn:setY(548)
        end
        self.cameraBtn:setVisible(active);self.focusBtn:setVisible(active);self.cutBtn:setVisible(active)
        if self.hudPosBtn then self.hudPosBtn:setVisible(active) end
    end
    function UI:cameraToggle() D.toggle() end
    function UI:focusToggle() D.toggleFocus() end
    function UI:nextCamera() D.nextShot() end

    function UI:drawPerformance(s,me)
        self.leaveBtn:setTitle('LEAVE / CLOSE')
        local w,h=self.width,self.height
        local config=B.difficulty(me.difficulty);local elapsed=C.elapsed(s)
        local song=B.song(s.song)
        local notes=B.notes(s.song,me.kind,me.difficulty)
        local prof=profileForKind(me.kind)
        local lanes=config.lanes
        local centered=(C.hudCentered~=false)

        -- Highway screen geometry
        local isHoriz=(prof.mode=='horizontal')
        local isRising=(prof.mode=='rising')
        local highwayW=isHoriz and math.min(720,w*.68) or math.min(410,w*.38)
        local center=centered and (w*.50) or (w-highwayW/2-34)
        local top=isHoriz and math.max(150,h*.28) or math.max(118,h*.20)
        local bottom=isHoriz and math.min(h-130,top+260) or (h-112)
        local length=math.max(120,bottom-top)
        local bottomHalf=highwayW/2;local topHalf=bottomHalf*(prof.topRatio or .48)
        local targetY=isRising and (top+34) or bottom
        local enterY=isRising and bottom or top
        local targetX=center-highwayW/2+42
        local rightX=center+highwayW/2-14

        -- Draw GH3 Top Song Banner
        local bannerW=math.min(620,w-140);local bannerX=(w-bannerW)/2
        self:drawRect(bannerX,12,bannerW,66,.88,.045,.018,.024)
        self:drawRect(bannerX,12,bannerW,3,1,.92,.70,.18)
        self:drawRect(bannerX,76,bannerW,2,1,.68,.12,.14)
        self:drawRectBorder(bannerX,12,bannerW,66,1,.78,.58,.18)
        local songLabel=string.upper(tostring(song.name or 'TRACK'))
        if song.artist then songLabel=songLabel..'  -  '..string.upper(tostring(song.artist)) end
        self:drawTextCentre(songLabel:sub(1,56),w/2,18,1,.93,.70,1,UIFont.Medium)
        -- Song progress bar & live star meter inside top banner
        local songDur=math.max(1,song.durationMs or 1000)
        local prog=math.max(0,math.min(1,elapsed/songDur))
        self:drawRect(bannerX+18,45,bannerW-36,8,.92,.09,.05,.06)
        self:drawRect(bannerX+18,45,(bannerW-36)*prog,8,1,.92,.22,.18)
        self:drawRect(bannerX+18,45,(bannerW-36)*prog,3,1,1,.74,.24)
        local remaining=math.max(0,math.ceil((songDur-elapsed)/1000))
        local countSec=math.max(1,math.ceil(-elapsed/1000))
        local timeTxt=elapsed<0 and ('IN '..countSec) or (math.floor(remaining/60)..':'..string.format('%02d',remaining%60))
        local maxPossible=math.max(1,#notes*120)
        local starRatio=(C.state.score or 0)/maxPossible
        local stars=(starRatio>=.85 and 5) or (starRatio>=.64 and 4) or (starRatio>=.42 and 3) or (starRatio>=.22 and 2) or (starRatio>=.08 and 1 or 0)
        local starStr=string.rep('*',stars)..string.rep('.',5-stars)
        local mSkill=B.musicSkill and getPlayer and B.musicSkill(getPlayer()) or {level=0,xp=0}
        self:drawText(prof.label..'  |  MUS '..tostring(mSkill.level or 0),bannerX+18,57,1,.82,.42,1,UIFont.Small)
        self:drawTextCentre('STARS ['..starStr..']',w/2,57,1,.88,.28,1,UIFont.Small)
        self:drawTextRight(timeTxt..'  |  '..config.name,bannerX+bannerW-18,57,.88,.92,.96,1,UIFont.Small)

        -- Draw Highway Backdrop according to instrument falling mode
        local steps=28
        if isHoriz then
            -- HORIZONTAL VOCAL STAFF (Right -> Left)
            local hBoxW=rightX-targetX+58
            self:drawRect(targetX-48,top,hBoxW,length,.84,prof.bg[1],prof.bg[2],prof.bg[3])
            self:drawRect(targetX-48,top,hBoxW,4,1,prof.rail[1],prof.rail[2],prof.rail[3])
            self:drawRect(targetX-48,bottom-4,hBoxW,4,1,prof.rail[1],prof.rail[2],prof.rail[3])
            -- Vertical Microphone Strikeline on the LEFT
            self:drawRect(targetX-6,top,12,length,.90,.16,.06,.12)
            self:drawRect(targetX-2,top,4,length,1,.96,.84,.36)
            -- Horizontal pitch lanes
            local laneNames={'LOW','MID','HIGH','PEAK'}
            for lane=1,lanes do
                local ly=top+(lane-.5)*(length/lanes)
                local col=colors[lane]
                self:drawRect(targetX,ly-1,rightX-targetX,2,.45,col[1],col[2],col[3])
                self:drawText(laneNames[lane] or tostring(lane),targetX-44,ly-8,col[1],col[2],col[3],1,UIFont.Small)
            end
            -- Beat vertical sweep bars (moving R -> L)
            local beatMs=60000/math.max(40,song.bpm or 120)
            local firstBeat=math.floor(math.max(0,elapsed)/beatMs)*beatMs
            for bt=firstBeat,elapsed+B.approachMs,beatMs do
                local p=1-(bt-elapsed)/B.approachMs
                if p>=0 and p<=1 then
                    local bx=rightX-(rightX-targetX)*p
                    self:drawRect(bx,top+4,2,length-8,.34,prof.fret[1],prof.fret[2],prof.fret[3])
                end
            end
        else
            -- VERTICAL HIGHWAY STRIPS (Supports perspective, straight piano-roll, rising wind, fan)
            for i=0,steps-1 do
                local p1=i/steps;local p2=(i+1)/steps
                local y1=top+length*p1;local y2=top+length*p2
                local wFrac1=isRising and (1-p1) or p1
                local wFrac2=isRising and (1-p2) or p2
                local half=(topHalf+(bottomHalf-topHalf)*((wFrac1+wFrac2)*.5))
                local shade=0.72+0.28*((wFrac1+wFrac2)*.5)
                self:drawRect(center-half,y1,half*2,y2-y1+1,.84,prof.bg[1]*shade,prof.bg[2]*shade,prof.bg[3]*shade)
                -- Acoustic soundhole subtle glow
                if prof.mode=='acoustic' and i>=10 and i<=19 then
                    self:drawRect(center-half*.34,y1,half*.68,y2-y1+1,.22,.02,.01,.01)
                elseif prof.mode=='banjo' then
                    self:drawRect(center-half*.62,y1,half*1.24,y2-y1+1,.22,.92,.88,.76)
                end
                -- Outer rails
                local railW=math.max(3,math.floor(3+((wFrac1+wFrac2)*.5)*3))
                self:drawRect(center-half,y1,railW,y2-y1+1,1,prof.rail[1],prof.rail[2],prof.rail[3])
                self:drawRect(center+half-railW,y1,railW,y2-y1+1,1,prof.rail[1],prof.rail[2],prof.rail[3])
            end

            -- Lane string / divider lines
            for lane=1,lanes-1 do
                local side=-1+(2*lane)/lanes
                local xTop=center+(isRising and bottomHalf or topHalf)*side
                local xBot=center+(isRising and topHalf or bottomHalf)*side
                drawSeg(self,xTop,top,xBot,bottom,.42,prof.fret[1],prof.fret[2],prof.fret[3])
            end

            -- Keyboard: Piano ivory/ebony key dividers at bottom strikeline
            if prof.mode=='pianoroll' then
                local slot=(bottomHalf*2)/lanes
                for lane=1,lanes do
                    local kx=center-bottomHalf+(lane-1)*slot
                    self:drawRect(kx+2,bottom-18,slot-4,34,.90,.92,.94,.96)
                    if lane<lanes then
                        self:drawRect(kx+slot-5,bottom-18,10,22,1,.06,.06,.09)
                    end
                end
            end

            -- Guitar / Acoustic inlay dots + Beat fret bars
            local beatMs=60000/math.max(40,song.bpm or 120)
            local firstBeat=math.floor(math.max(0,elapsed)/beatMs)*beatMs
            for bt=firstBeat,elapsed+B.approachMs,beatMs do
                local rawP=1-(bt-elapsed)/B.approachMs
                if rawP>=0 and rawP<=1 then
                    local ep=rawP^(prof.exp or 1.25)
                    local y=isRising and (bottom-length*ep) or (top+length*ep)
                    local half=topHalf+(bottomHalf-topHalf)*(isRising and (1-ep) or ep)
                    local measureBeat=(math.floor(bt/beatMs+.5)%4==0)
                    local alpha=measureBeat and .68 or .28
                    local thick=measureBeat and 3 or 2
                    self:drawRect(center-half+3,y,half*2-6,thick,alpha,prof.fret[1],prof.fret[2],prof.fret[3])
                    if prof.mode=='guitar' and measureBeat and half>60 then
                        self:drawRect(center-4,y-4,8,8,.45,.90,.88,.82)
                    end
                end
            end

            -- Strikeline target track bar
            local stHalf=isRising and topHalf or bottomHalf
            self:drawRect(center-stHalf-6,targetY-5,stHalf*2+12,10,.88,.08,.03,.04)
            self:drawRect(center-stHalf-4,targetY-1,stHalf*2+8,3,1,.92,.72,.22)
        end

        -- Coordinate mapper helper for a note (per-instrument trajectory!)
        local function notePosition(note,rawP)
            local ep=rawP^(prof.exp or 1.25)
            local lanePos=(note.lane-.5)/lanes*2-1
            if isHoriz then
                local nx=rightX-(rightX-targetX)*ep
                local ny=top+(note.lane-.5)*(length/lanes)
                return nx,ny,1.0
            elseif isRising then
                local ny=bottom-length*ep
                local wFrac=1-ep
                local half=topHalf+(bottomHalf-topHalf)*wFrac
                local nx=center+half*lanePos
                return nx,ny,0.58+0.42*ep
            else
                local ny=top+length*ep
                local half=topHalf+(bottomHalf-topHalf)*ep
                local nx=center+half*lanePos
                -- Smooth convergent curve so notes ALWAYS land dead-on target at rawP==1.0
                local converge=math.max(0,1-rawP)
                if prof.waveAmp then
                    nx=nx+math.sin(rawP*6.283+(note.lane*1.1))*prof.waveAmp*converge
                elseif prof.sway then
                    nx=nx+math.cos(rawP*3.1415+note.lane)*prof.sway*converge
                end
                return nx,ny,0.52+0.48*ep
            end
        end

        -- Draw approaching & slightly passed notes
        for i=C.state.cursor or 1,#notes do
            local note=notes[i]
            if not C.state.judged[note.index] then
                local delta=note.t-elapsed
                if delta>B.approachMs then break end
                if delta>=-240 then
                    local rawP=math.max(0,math.min(1.14,1-delta/B.approachMs))
                    local nx,ny,scale=notePosition(note,rawP)
                    local col=colors[note.lane] or colors[1]
                    local starPulse=(note.index%8==0 and (C.state.combo or 0)>=8)
                    if prof.kickBar and note.lane==1 then
                        -- DRUMS: Iconic full-width orange Kick Pedal Bar!
                        local half=topHalf+(bottomHalf-topHalf)*(rawP^(prof.exp or 1.28))
                        local bw=(half*2)-10
                        local bh=math.max(7,math.floor(11*scale))
                        self:drawRect(center-bw/2,ny-bh/2,bw,bh,1,1,.46,.10)
                        self:drawRect(center-bw/2+4,ny-2,bw-8,3,1,1,.88,.48)
                        self:drawRectBorder(center-bw/2,ny-bh/2,bw,bh,1,.20,.08,.02)
                    elseif prof.heavy then
                        -- BASS: Tall heavy metallic brick slab
                        local bw=math.floor(42*scale);local bh=math.floor(20*scale)
                        self:drawRect(nx-bw/2,ny-bh/2,bw,bh,1,col[1]*.85,col[2]*.85,col[3]*.85)
                        self:drawRect(nx-bw/2+4,ny-bh/2+3,bw-8,5,1,1,1,1)
                        self:drawRectBorder(nx-bw/2,ny-bh/2,bw,bh,1,.05,.05,.08)
                    else
                        -- Textured GH3 Gem / Instrument Note Sprite + crisp procedural fallback
                        local size=math.floor(32*scale)
                        local nw=prof.mode=='pianoroll' and math.floor(size*1.12) or (isHoriz and math.floor(size*1.28) or size)
                        local nh=isHoriz and math.floor(size*.84) or size
                        local texPath=nil
                        if starPulse and prof.directGems then
                            texPath='media/ui/ZombBand/GH3_Gem_Star.png'
                        elseif prof.directGems and prof.noteTex then
                            texPath=prof.noteTex..tostring(math.min(5,note.lane))..'.png'
                        else
                            texPath=prof.noteTex
                        end
                        local tex=getTex(texPath)
                        if tex then
                            local tr,tg,tb=1,1,1
                            if not prof.directGems then tr,tg,tb=col[1],col[2],col[3] end
                            self:drawTextureScaled(tex,nx-nw/2,ny-nh/2,nw,nh,1,tr,tg,tb)
                        else
                            self:drawRect(nx-nw/2,ny-nh/2,nw,nh,1,col[1],col[2],col[3])
                            self:drawRect(nx-nw/4,ny-nh/4,nw/2,nh/2,1,.98,.98,1)
                            self:drawRectBorder(nx-nw/2,ny-nh/2,nw,nh,1,.08,.08,.10)
                        end
                    end
                end
            end
        end

        -- Draw Strikeline Receptors, Key Labels & GH3 Hit Flames
        local now=B.now()
        local flameTex=getTex('media/ui/ZombBand/GH3_Flame.png')
        local laneKeys=prof.kickBar and {'1/SP','2/S','3/D','4/F','5/G'} or {'1/A','2/S','3/D','4/F','5/G'}
        for lane=1,lanes do
            local col=colors[lane] or colors[1]
            local rx,ry,rw,rh
            if isHoriz then
                rx=targetX;ry=top+(lane-.5)*(length/lanes)
                rw=30;rh=24
            else
                local lanePos=(lane-.5)/lanes*2-1
                local stHalf=isRising and topHalf or bottomHalf
                rx=center+stHalf*lanePos;ry=targetY
                rw=math.floor(math.min(48,(stHalf*2/lanes)*.78));rh=24
            end
            local flash=C.laneFlashes and C.laneFlashes[lane]
            local age=flash and (now-flash.at) or 9999
            local activeFlash=age<240
            self:drawRect(rx-rw/2,ry-rh/2,rw,rh,.92,.06,.05,.07)
            self:drawRectBorder(rx-rw/2,ry-rh/2,rw,rh,1,col[1],col[2],col[3])
            if activeFlash then
                local fa=1-age/240
                self:drawRect(rx-rw/2+2,ry-rh/2+2,rw-4,rh-4,.88*fa,col[1],col[2],col[3])
                if flash.hit then
                    if flameTex then
                        self:drawTextureScaled(flameTex,rx-36,ry-66,72,72,.92*fa,1,1,1)
                    else
                        self:drawRect(rx-18,ry-48,36,36,.75*fa,1,.62,.16)
                        self:drawRect(rx-10,ry-36,20,24,.85*fa,1,.95,.55)
                    end
                end
            else
                self:drawRect(rx-rw/2+5,ry-5,rw-10,10,.60,col[1],col[2],col[3])
            end
            if isHoriz then
                self:drawText(tostring(lane),rx-24,ry-7,1,.95,.82,1,UIFont.Small)
            else
                local labelY=isRising and (ry-28) or (ry+18)
                self:drawTextCentre(laneKeys[lane] or tostring(lane),rx,labelY,.92,.92,.96,1,UIFont.Small)
            end
        end

        -- Guitar Hero III Left HUD Stack: Score + Multiplier Badge + Rock Meter
        local rock=C.state.rock or 100
        local combo=C.state.combo or 0
        local mult=B.multiplier(combo)
        local nextTier=(combo>=30 and 10) or (combo%10)
        local hudX=centered and math.max(16,center-bottomHalf-238) or 18
        if hudX<14 then hudX=14 end
        local hudW=208;local hudY=math.max(92,top)

        -- 1) GH3 Score Box + Combo Multiplier Circle/Plaque
        self:drawRect(hudX,hudY,hudW,128,.90,.04,.02,.03)
        self:drawRect(hudX,hudY,hudW,4,1,.92,.70,.18)
        self:drawRectBorder(hudX,hudY,hudW,128,1,.78,.56,.18)
        self:drawText('SCORE',hudX+14,hudY+10,1,.88,.36,1,UIFont.Small)
        self:drawText(formatScore(C.state.score),hudX+14,hudY+26,1,.98,.94,1,UIFont.Large)

        -- Multiplier Badge + 10-pip Charge Bar
        local mCol=mult>=4 and {.96,.68,.18} or (mult==3 and {.22,.92,.38} or (mult==2 and {.26,.74,1} or {.62,.62,.68}))
        self:drawRect(hudX+14,hudY+64,54,48,.96,.09,.05,.07)
        self:drawRectBorder(hudX+14,hudY+64,54,48,1,mCol[1],mCol[2],mCol[3])
        self:drawTextCentre(mult..'X',hudX+41,hudY+73,mCol[1],mCol[2],mCol[3],1,UIFont.Large)
        self:drawText('STREAK: '..combo,hudX+78,hudY+66,1,.92,.70,1,UIFont.Small)
        for pip=1,10 do
            local px=hudX+78+(pip-1)*11.5
            local lit=pip<=nextTier or mult>=4
            self:drawRect(px,hudY+88,9,14,lit and 1 or .25,lit and mCol[1] or .3,lit and mCol[2] or .3,lit and mCol[3] or .35)
        end
        if combo>=10 then
            self:drawText('NOTE STREAK!!',hudX+78,hudY+106,1,.95,.35,1,UIFont.Small)
        else
            self:drawText('MAX '..(C.state.maxCombo or 0)..' / MISS '..(C.state.misses or 0),hudX+78,hudY+106,.75,.82,.88,1,UIFont.Small)
        end

        -- 2) GH3 ROCK METER (Arch Dial with Rotating Needle)
        local rmY=hudY+140
        self:drawRect(hudX,rmY,hudW,136,.90,.04,.02,.03)
        self:drawRectBorder(hudX,rmY,hudW,136,1,.78,.56,.18)
        local dangerBlink=rock<28 and ((math.floor(now/180)%2)==0)
        local rockLabel=rock<28 and '!! DANGER !!' or (rock>=80 and 'ROCKING!' or 'ROCK METER')
        local rlCol=dangerBlink and {1,.2,.18} or (rock>=80 and {1,.88,.25} or {.90,.74,.40})
        self:drawTextCentre(rockLabel,hudX+hudW/2,rmY+8,rlCol[1],rlCol[2],rlCol[3],1,UIFont.Small)

        local gaugeX=hudX+10;local gaugeY=rmY+26;local gaugeW=hudW-20;local gaugeH=96
        local rmTex=getTex('media/ui/ZombBand/GH3_RockMeter.png')
        if rmTex then
            self:drawTextureScaled(rmTex,gaugeX,gaugeY,gaugeW,gaugeH,1,1,1,1)
        else
            self:drawRect(gaugeX+8,gaugeY+46,(gaugeW-16)/3,18,.95,.82,.14,.14)
            self:drawRect(gaugeX+8+(gaugeW-16)/3,gaugeY+46,(gaugeW-16)/3,18,.95,.92,.76,.16)
            self:drawRect(gaugeX+8+2*(gaugeW-16)/3,gaugeY+46,(gaugeW-16)/3,18,.95,.18,.84,.30)
            self:drawRectBorder(gaugeX+8,gaugeY+46,gaugeW-16,18,1,.90,.70,.22)
        end
        -- Needle from -pi/2 (rock=0, left) through 0 (rock=50, up) to +pi/2 (rock=100, right)
        local pivotX=gaugeX+gaugeW/2;local pivotY=gaugeY+gaugeH-11
        local frac=math.max(0,math.min(1,rock/100))
        local ang=math.pi*(1-frac) -- pi (left) .. 0 (right)
        local tipX=pivotX+math.cos(ang)*62
        local tipY=pivotY-math.sin(ang)*62
        drawSeg(self,pivotX-1,pivotY,tipX,tipY,1,1,.95,.80)
        drawSeg(self,pivotX,pivotY,tipX,tipY,1,1,.25,.15)
        drawSeg(self,pivotX+1,pivotY,tipX,tipY,1,1,.95,.80)
        self:drawRect(pivotX-5,pivotY-5,10,10,1,.95,.78,.24)
        self:drawText(tostring(rock)..'%',hudX+hudW-42,rmY+116,.85,.88,.92,1,UIFont.Small)

        -- 3) Camera & Calibration compact line below HUD
        self:drawText(tostring(D.label):sub(1,28),hudX+6,rmY+144,.82,.72,.52,1,UIFont.Small)

        -- Countdown Overlay (3 - 2 - 1 - ROCK!)
        if elapsed<0 then
            local cy=top+length*.42
            self:drawRect(center-110,cy-42,220,86,.92,.06,.015,.025)
            self:drawRect(center-110,cy-42,220,4,1,.96,.72,.20)
            self:drawRectBorder(center-110,cy-42,220,86,1,.90,.66,.18)
            self:drawTextCentre(tostring(math.min(3,countSec)),center,cy-30,1,.90,.24,1,UIFont.Large)
            self:drawTextCentre(string.upper(B.kindNames[me.kind] or me.kind)..'  -  '..prof.label,center,cy+14,1,.84,.48,1,UIFont.Small)
        elseif elapsed<650 then
            local cy=top+length*.36
            self:drawTextCentre('ROCK!!',center,cy,1,.92,.22,1,UIFont.Large)
        end

        -- Judgement Text below Strikeline
        if now-C.lastJudgementAt<800 then
            local j=C.lastJudgement
            local jr,jg,jb=1,.90,.35
            if j=='MISS' or j=='OVERHIT' then jr,jg,jb=1,.24,.22
            elseif j=='GOOD' then jr,jg,jb=.45,.90,1 end
            self:drawTextCentre(j,center,isHoriz and (bottom+16) or (isRising and (top-24) or (bottom+44)),jr,jg,jb,1,UIFont.Medium)
        end

        if C.audioError then self:drawText(C.audioError:sub(1,95),16,h-68,1,.4,.35,1,UIFont.Small) end
        self.cameraBtn:setTitle(D.enabled and 'CAMERA ON' or 'CAMERA OFF')
        self.focusBtn:setTitle(D.focus=='self' and 'FOCUS: ME' or 'FOCUS: BAND')
        if self.hudPosBtn then self.hudPosBtn:setTitle(centered and 'HUD: CENTER' or 'HUD: SIDE') end
    end

    function UI:drawMenu(s,me)
        -- Fallback menu (normally overridden by HUNKBand_LibraryUI)
        local setup=not s or s.phase=='lobby';local host=s and s.host==C.selfKey()
        local function place(child,x,y,width) child:setX(x);child:setY(y);if width then child:setWidth(width) end end
        place(self.songBox,28,128,390);place(self.diffBox,28,194,260)
        place(self.minusBtn,300,194);place(self.plusBtn,386,194)
        place(self.bandBox,28,260,390);place(self.audioTestBtn,464,292,242)
        place(self.playBtn,28,548,125);place(self.formBtn,163,548,125);place(self.joinBtn,298,548,125)
        place(self.replayBtn,28,548,190)
        self.songBox:setVisible(setup);self.diffBox:setVisible(setup);self.audioTestBtn:setVisible(setup)
        self.minusBtn:setVisible(setup);self.plusBtn:setVisible(setup);self.bandBox:setVisible(not s)
        self.songBox:setEnabled(not s or host);self.playBtn:setVisible(setup and (not s or host))
        self.formBtn:setVisible(not s);self.joinBtn:setVisible(not s);self.replayBtn:setVisible(s~=nil and s.phase=='results' and host)
        self.playBtn:setEnable(not C.pendingAction and (not isClient() or #C.samples>=3))
        for _,child in ipairs({self.playBtn,self.formBtn,self.joinBtn,self.replayBtn,self.audioTestBtn,self.cameraBtn,self.focusBtn,self.cutBtn}) do
            child.backgroundColor={r=.09,g=.03,b=.04,a=.97};child.borderColor={r=.86,g=.62,b=.18,a=1}
            child.backgroundColorMouseOver={r=.20,g=.06,b=.07,a=1}
        end
        self.playBtn.backgroundColor={r=.48,g=.08,b=.06,a=1};self.playBtn.borderColor={r=1,g=.72,b=.18,a=1}
        self.playBtn:setTitle(s and 'START SET' or 'PLAY SOLO')
        self:drawRect(0,0,self.width,self.height,.98,.035,.012,.018)
        self:drawRectBorder(0,0,self.width,self.height,1,.78,.56,.18)
        self:drawRect(0,0,self.width,4,1,.92,.70,.18)
        self:drawText('ZOMB-BAND III',30,19,1,.88,.34,1,UIFont.Large)
        self:drawText('LEGENDS OF THE APOCALYPSE',31,53,.90,.74,.52,1,UIFont.Small)
        self:drawText(s and ('BAND '..#s.members..'/6') or 'QUICKPLAY',540,30,1,.88,.34,1,UIFont.Medium)
        if s and s.phase=='results' then
            self:drawText('SET COMPLETE',28,112,1,.92,.36,1,UIFont.Large)
            for i,m in ipairs(s.members) do
                local accuracy=math.floor(m.hits/math.max(1,#B.notes(s.song,m.kind,m.difficulty))*100+.5)
                self:drawRect(28,168+(i-1)*52,704,44,.88,.08,.025,.035)
                self:drawText(m.name..'  /  '..m.score..' PTS  /  '..accuracy..'%  /  BEST '..m.maxCombo,44,177+(i-1)*52,1,.94,.76,1,UIFont.Medium)
            end
        end
        if C.audioError then self:drawText(C.audioError:sub(1,93),28,511,1,.36,.28,1,UIFont.Small)
        else self:drawText(tostring(C.status):sub(1,95),28,511,.90,.80,.66,1,UIFont.Small) end
    end
end
