require 'ISUI/ISTextEntryBox'
return function(UI,C,B,D,L)
    local function button(self,label,callback)
        local wrapped=function(...) if C.menuCue then C.menuCue('select') end;return callback(...) end
        local b=ISButton:new(0,0,100,28,label,self,wrapped)
        b:initialise();b:instantiate();self:addChild(b)
        b.backgroundColor={r=.025,g=.09,b=.16,a=1};b.borderColor={r=.12,g=.42,b=.65,a=1}
        b.backgroundColorMouseOver={r=.08,g=.25,b=.38,a=1}
        return b
    end
    local function place(child,x,y,w,h)
        child:setX(x);child:setY(y);if w then child:setWidth(w) end;if h then child:setHeight(h) end
    end
    local function clip(text,limit)
        text=tostring(text or '');if #text>limit then return text:sub(1,math.max(1,limit-3))..'...' end
        return text
    end
    local function fontHeight(font,fallback)
        if getTextManager then local manager=getTextManager()
            if manager and manager.getFontHeight then return manager:getFontHeight(font) end
        end
        return fallback
    end
    function UI:createLibrary()
        if self.searchEntry then return end
        self.searchEntry=ISTextEntryBox:new('',0,0,180,28)
        self.searchEntry:initialise();self.searchEntry:instantiate();self:addChild(self.searchEntry)
        self.searchEntry:setPlaceholderText('Search title, artist or source...')
        self.searchEntry.target=self
        self.searchEntry.onTextChangeFunction=function(owner,entry)
            L.query=entry:getText();L.scroll=0;owner.librarySignature=nil
        end
        self.librarySort=ISComboBox:new(0,0,132,28,self,function(owner) L.sort=owner.librarySort.selected;L.scroll=0;owner.librarySignature=nil end)
        self.librarySort:initialise();self.librarySort:instantiate();self:addChild(self.librarySort)
        for _,name in ipairs(L.sorts) do self.librarySort:addOption(name) end
        self.styleBtn=button(self,'STYLE',function(owner) L.cycleStyle();owner.librarySignature=nil end)
        self.randomBtn=button(self,'RANDOM SONG',function() L.random(C) end)
        self.queueBtn=button(self,'+ TO SETLIST',function() if L.addQueue(L.selected) then C.status='Added to next-up setlist ('..#L.queue..'). The selected song plays first.' end end)
        self.clearQueueBtn=button(self,'CLEAR QUEUE',function() L.queue={};local band=C.getSession();if band and band.host==C.selfKey() and band.phase=='lobby' then C.send('setlist',{id=band.id,songs={}}) end end)
        self.detailsBtn=button(self,'DETAILS: INFO',function(owner) owner.detailPage=(owner.detailPage or 1)%4+1;owner.detailScroll=0 end)
        self.instrumentBtn=button(self,'INSTRUMENT',UI.nextInstrument)
        self.playlistName=ISTextEntryBox:new('My Setlist',0,0,100,24)
        self.playlistName:initialise();self.playlistName:instantiate();self:addChild(self.playlistName)
        self.playlistName:setPlaceholderText('Playlist name')
        self.saveListBtn=button(self,'SAVE QUEUE',function(owner) if L.savePlaylist(owner.playlistName:getText()) then C.status='Saved '..L.playlistName..' ('..#L.queue..' songs).' end end)
        self.loadListBtn=button(self,'LOAD LIST',function(owner) if not L.loadPlaylist(owner.playlistName:getText()) then C.status='No saved playlist with that name.' end end)
        self.playlistSongBtn=button(self,'+/- PLAYLIST',function(owner) L.playlistName=owner.playlistName:getText();if L.selected then L.togglePlaylist(L.selected);owner.librarySignature=nil end end)
        self.favoriteBtn=button(self,'FAVORITE',UI.favoriteSong)
        self.previewBtn=button(self,'PREVIEW INTRO',UI.previewSong)
        self.cameraTestBtn=button(self,'CAMERA CHECK',UI.checkCamera)
        self.clearSearchBtn=button(self,'CLEAR',UI.clearSearch)
        self.collectionBox=ISComboBox:new(0,0,122,26,self,function(owner) L.filter=owner.collectionBox.selected;L.scroll=0;owner.librarySignature=nil;C.stopPreview() end)
        self.collectionBox:initialise();self.collectionBox:instantiate();self:addChild(self.collectionBox)
        for _,name in ipairs(L.categories) do self.collectionBox:addOption(name) end
        self.categoryButtons={}
        for index=1,math.min(9,#L.categories) do
            local name=L.categories[index]
            local category=index
            self.categoryButtons[index]=button(self,name,function(owner)
                L.filter=category;L.scroll=0;owner.librarySignature=nil;C.stopPreview()
            end)
        end
    end
    function UI:nextInstrument()
        local choices={};for item,kind in pairs(B.vanillaInstruments) do if B.hasInstrument(getPlayer(),item,4.0) then choices[#choices+1]=item end end
        table.sort(choices);if #choices==0 then C.status='No supported instrument in your inventory or nearby.';return end
        local index=0;for i,item in ipairs(choices) do if item==C.itemType then index=i end end
        local item=choices[index%#choices+1];local band=C.getSession()
        if band and (band.phase=='lobby' or band.phase=='results') then C.startWhenReady=false;C.send('instrument',{id=band.id,itemType=item})
        elseif not band then C.itemType=item else C.status='Change instruments in the waiting lobby.';return end
        self.librarySignature=nil
    end
    function UI:cycleSort() L.sort=L.sort%#L.sorts+1;L.scroll=0;self.librarySignature=nil end
    function UI:favoriteSong()
        if L.selected then L.favorite(L.selected);self.librarySignature=nil end
    end
    function UI:previewSong()
        if not L.selected then return end
        if C.previewVoice and C.previewVoice.song==L.selected then C.stopPreview()
        else C.previewAudio(L.selected) end
    end
    function UI:checkCamera() C.stopPreview();self.searchEntry:unfocus();D.test(C) end
    function UI:clearSearch()
        self.searchEntry:setText('');L.query='';L.filter=1;L.scroll=0;self.librarySignature=nil
    end
    function UI:libraryKind()
        local s=C.getSession();local me=C.me(s)
        if me then return me.kind end
        if C.roleOverride and B.roleToKind and B.roleToKind[C.roleOverride] then return B.roleToKind[C.roleOverride] end
        return B.instrumentKind(C.itemType) or 'acoustic'
    end
    function UI:refreshLibrary()
        local kind=self:libraryKind();local me=C.me(C.getSession());local band=C.getSession();local difficulty=me and band and band.phase~='results' and me.difficulty or C.difficulty
        local signature=L.filter..':'..L.sort..':'..L.query..':'..L.revision..':'..kind..':'..difficulty
        if signature~=self.librarySignature then
            local selected=L.selected
            self.librarySignature=signature;L.rebuild(kind,difficulty);L.ensureVisible()
            if selected~=L.selected then C.stopPreview() end
        end
    end
    local oldChildren=UI.createChildren
    function UI:createChildren() oldChildren(self);self:createLibrary() end
    local oldLayout=UI.layoutPerformance
    function UI:layoutPerformance(active)
        oldLayout(self,active)
        self.moveWithMouse=false
        if not active then
            local w=math.min(1660,getCore():getScreenWidth()-40)
            local h=math.min(940,getCore():getScreenHeight()-40)
            self:setWidth(w);self:setHeight(h)
            self:setX((getCore():getScreenWidth()-w)/2);self:setY((getCore():getScreenHeight()-h)/2)
            place(self.closeBtn,w-44,22,28,28)
        end
        for _,child in ipairs({self.searchEntry,self.librarySort,self.favoriteBtn,self.previewBtn,self.cameraTestBtn,self.clearSearchBtn,self.styleBtn,self.randomBtn,self.queueBtn,self.clearQueueBtn,self.detailsBtn,self.instrumentBtn,self.playlistName,self.saveListBtn,self.loadListBtn,self.playlistSongBtn,self.collectionBox}) do child:setVisible(not active) end
        for _,child in ipairs(self.categoryButtons) do child:setVisible(not active) end
    end
    function UI:drawMenu(s,me)
        self:refreshLibrary()
        local w,h=self.width,self.height;local panelW=math.max(246,math.floor((w-174)*.31));local right=w-panelW-12;local listX=160;local listW=right-listX-20
        local style=L.style();local gh3=style==1;local paper=style==3;local arcade=style==4
        local titleFont=paper and (UIFont.Handwritten or UIFont.Medium) or UIFont.Medium
        local smallH=fontHeight(UIFont.Small,16);local mediumH=fontHeight(titleFont,paper and 32 or 22)
        local footer=h-112;local top=174;local rowH=math.max(52,smallH+mediumH+10)
        L.pageSize=math.max(3,math.floor((footer-36-top)/rowH))
        L.scroll=math.min(L.scroll,math.max(0,#L.rows-L.pageSize));L.ensureVisible()
        self.libraryRect={x=listX,y=top,w=listW,h=L.pageSize*rowH,rowH=rowH}
        local host=s and s.host==C.selfKey();local results=s and s.phase=='results'
        local setup=not s or s.phase=='lobby' or results
        self.leaveBtn:setVisible(true);self.closeBtn:setVisible(true)
        self.leaveBtn:setTitle(s and 'LEAVE BAND' or 'CLOSE')
        local btnBg=gh3 and {r=.10,g=.02,b=.03,a=1} or (arcade and {r=.11,g=.03,b=.11,a=1} or {r=.025,g=.09,b=.16,a=1})
        local btnBorder=gh3 and {r=.86,g=.62,b=.16,a=1} or (arcade and {r=.95,g=.22,b=.62,a=1} or {r=.12,g=.42,b=.65,a=1})
        local btnOver=gh3 and {r=.26,g=.05,b=.06,a=1} or {r=.08,g=.25,b=.38,a=1}
        for _,child in ipairs({self.playBtn,self.formBtn,self.joinBtn,self.replayBtn,self.leaveBtn,self.minusBtn,self.plusBtn}) do
            child.backgroundColor=btnBg;child.borderColor=btnBorder;child.backgroundColorMouseOver=btnOver
        end
        if gh3 then
            self.playBtn.backgroundColor={r=.56,g=.07,b=.06,a=1};self.playBtn.borderColor={r=1,g=.76,b=.22,a=1}
        else
            self.playBtn.backgroundColor={r=.36,g=.07,b=.23,a=1};self.playBtn.borderColor={r=1,g=.23,b=.52,a=1}
        end
        for _,child in ipairs({self.songBox,self.audioTestBtn,self.replayBtn}) do child:setVisible(false) end
        self.diffBox:setVisible(setup);self.minusBtn:setVisible(setup);self.plusBtn:setVisible(setup)
        self.playBtn:setVisible(setup and (not s or host));self.formBtn:setVisible(not s);self.joinBtn:setVisible(not s)
        self.bandBox:setVisible(not s);self.replayBtn:setVisible(false)
        self.playBtn:setEnable(C.startWhenReady and s and s.phase=='lobby' and host or not C.pendingAction and L.selected~=nil and L.playable(L.selected,self:libraryKind(),C.difficulty) )
        self.queueBtn:setEnable(L.selected~=nil and (not s or host) and setup);self.favoriteBtn:setEnable(L.selected~=nil);self.previewBtn:setEnable(L.selected~=nil and setup)
        self.playBtn:setTitle(C.startWhenReady and s and s.phase=='lobby' and 'CANCEL WAIT' or results and 'PLAY SELECTED' or s and (L.selected and L.selected~=s.song and 'SET TRACK' or 'START BAND') or (gh3 and 'ROCK OUT!' or 'PLAY SOLO'))
        self.librarySort.selected=L.sort
        self.styleBtn:setTitle('STYLE: '..(L.styles[style] or 'GH3'))
        self.detailsBtn:setTitle(({'INFO','PARTS','RECORDS','BAND / QUEUE'})[self.detailPage or 1]..' >')
        self.instrumentBtn:setTitle(clip(B.kindNames[self:libraryKind()] or 'Instrument',22))
        self.favoriteBtn:setTitle(L.selected and L.isFavorite(L.selected) and '* FAVORITED' or '+ FAVORITE')
        self.previewBtn:setTitle(C.previewVoice and 'STOP PREVIEW' or 'PREVIEW INTRO')
        place(self.searchEntry,listX,104,math.max(80,listW-196),28)
        place(self.clearSearchBtn,listX+listW-190,104,52,28)
        place(self.librarySort,listX+listW-132,104,132,28)
        place(self.cameraTestBtn,w-205,22,144,28)
        place(self.styleBtn,w-415,22,200,28)
        self.collectionBox:setVisible(true);self.collectionBox.selected=L.filter
        place(self.collectionBox,20,h<700 and 158 or 374,122,26)
        for i,b in ipairs(self.categoryButtons) do b:setVisible(h>=700);place(b,20,156+(i-1)*23,122,21)
            if gh3 then
                b.backgroundColor=i==L.filter and {r=.52,g=.09,b=.08,a=1} or {r=.075,g=.02,b=.025,a=1}
                b.borderColor=i==L.filter and {r=1,g=.76,b=.22,a=1} or {r=.45,g=.28,b=.10,a=1}
            else
                b.backgroundColor=i==L.filter and {r=.08,g=.28,b=.43,a=1} or {r=.025,g=.065,b=.10,a=1}
            end
        end
        local detailW=panelW-24
        place(self.randomBtn,20,104,122,28)
        local playlistY=h<700 and 204 or 414
        place(self.playlistName,20,playlistY,122,24);place(self.saveListBtn,20,playlistY+28,122,24);place(self.loadListBtn,20,playlistY+56,122,24)
        place(self.playlistSongBtn,20,playlistY+84,122,24)
        place(self.detailsBtn,right+12,104,detailW,26)
        place(self.favoriteBtn,right+12,footer-68,detailW/2-3,26)
        place(self.queueBtn,right+15+detailW/2,footer-68,detailW/2-3,26)
        place(self.clearQueueBtn,20,footer-32,122,26)
        place(self.instrumentBtn,430,footer+50,math.max(56,right-438),26)
        self.instrumentBtn:setVisible(setup)
        place(self.previewBtn,right+12,footer-36,detailW,26)
        place(self.playBtn,20,footer+10,132,30);place(self.formBtn,162,footer+10,120,30);place(self.joinBtn,292,footer+10,120,30)
        place(self.replayBtn,20,footer+10,192,30)
        place(self.bandBox,20,footer+50,392,26)
        place(self.diffBox,right+12,footer+10,detailW,26)
        place(self.minusBtn,right+12,footer+50,28,26);place(self.plusBtn,right+98,footer+50,28,26)
        place(self.leaveBtn,right+134,footer+50,detailW-122,26)
        self.diffBox:setEnabled(not results or host)
        if me and not results then self.diffBox.selected=me.difficulty else self.diffBox.selected=C.difficulty end
        self.openAt=self.openAt or B.now();local fade=math.min(1,(B.now()-self.openAt)/180)
        if gh3 then
            self:drawRect(0,0,w,h,.92+fade*.04,.025,.009,.014)
            if self.drawLine2 then
                for x=40,w-60,150 do
                    self:drawLine2(x,76,x+90,footer-4,.22,.78,.14,.10)
                    self:drawLine2(x+110,76,x+10,footer-4,.18,.95,.68,.18)
                end
            end
        else
            self:drawRect(0,0,w,h,.89+fade*.04,paper and .84 or .013,paper and .82 or .024,paper and .71 or .043)
            if paper then for y=142,footer-10,24 do self:drawRect(14,y,w-28,1,.25,.16,.35,.56) end
            elseif arcade then
                for x=16,w-32,64 do self:drawRect(x,74,2,footer-78,.24,.8,.12,.47) end
                if self.drawLine2 then for x=20,w-80,110 do
                    self:drawLine2(x,footer-38,x+65,footer-98,.7,1,.24,.62)
                    self:drawLine2(x+65,footer-98,x+44,footer-34,.7,.3,.8,1)
                end end
            end
        end
        self:drawRect(14,footer-2,w-28,h-footer+2,.96,gh3 and .038 or .014,gh3 and .012 or .03,gh3 and .018 or .055)
        self:drawRectBorder(0,0,w,h,1,gh3 and .82 or .16,gh3 and .56 or .38,gh3 and .16 or .58)
        for y=4,74,4 do
            local rCol=gh3 and (.18+(74-y)*.0022) or (arcade and .19 or .02)
            local gCol=gh3 and .022 or (arcade and .025 or .08+(74-y)*.0007)
            local bCol=gh3 and .028 or (arcade and .16 or .15+(74-y)*.001)
            self:drawRect(4,y,w-8,4,1,rCol,gCol,bCol)
        end
        self:drawRect(0,0,w,4,1,gh3 and .96 or (arcade and 1 or .12),gh3 and .74 or (arcade and .22 or .72),gh3 and .18 or (arcade and .58 or 1))
        local titleOffset=22
        if gh3 then
            self.artCache=self.artCache or {}
            local emblem=self.artCache.gh3Emblem
            if emblem==nil then emblem=getTexture and getTexture('media/ui/ZombBand/GH3_Emblem.png') or false;self.artCache.gh3Emblem=emblem end
            if emblem then self:drawTextureScaled(emblem,16,8,62,62,1,1,1,1);titleOffset=86 end
        end
        self:drawText(gh3 and 'ZOMB-BAND III  /  SETLIST' or 'MUSIC LIBRARY',titleOffset,17,1,gh3 and .92 or 1,gh3 and .68 or 1,1,UIFont.Large)
        self:drawText(gh3 and 'LEGENDS OF THE APOCALYPSE  /  HUNK' or 'ZOMB-BAND / HUNK',titleOffset+3,53,gh3 and .92 or .40,gh3 and .34 or .78,gh3 and .24 or 1,1,UIFont.Small)
        local complete,mastered=L.completed(self:libraryKind(),C.difficulty)
        local mSkill=B.musicSkill and getPlayer and B.musicSkill(getPlayer()) or {level=0,xp=0}
        self:drawText(#B.songs..' SONGS / '..complete..' COMPLETE / '..mastered..' MASTERED / MUSICA NVL '..tostring(mSkill.level or 0)..' / '..L.sorts[L.sort],titleOffset+245,54,gh3 and .92 or .62,gh3 and .76 or .77,gh3 and .48 or .89,1,UIFont.Small)
        self:drawText('COLLECTION',22,138,paper and .1 or (gh3 and .92 or .54),paper and .2 or (gh3 and .68 or .68),paper and .3 or (gh3 and .24 or .78),1,UIFont.Small)
        self:drawRect(listX,145,listW,25,1,gh3 and .22 or .035,gh3 and .04 or .105,gh3 and .045 or .17)
        self:drawText('TRACK / ARTIST',listX+14,149,gh3 and .96 or .55,gh3 and .78 or .77,gh3 and .32 or .92,1,UIFont.Small)
        local durationX=listX+listW-112;local bestX=listX+listW-42
        self:drawTextCentre('LENGTH',durationX,149,gh3 and .96 or .55,gh3 and .78 or .77,gh3 and .32 or .92,1,UIFont.Small)
        self:drawTextCentre('BEST',bestX,149,gh3 and .96 or .55,gh3 and .78 or .77,gh3 and .32 or .92,1,UIFont.Small)
        local kind=self:libraryKind();local band=C.getSession();local difficulty=me and band and band.phase~='results' and me.difficulty or C.difficulty
        local ghFrets={{.16,.92,.32},{.98,.20,.23},{1,.84,.16},{.20,.56,1},{1,.48,.12}}
        for display=1,L.pageSize do
            local row=L.rows[L.scroll+display];local y=top+(display-1)*rowH
            if row then
                local selected=row.id==L.selected
                local rowR=selected and (gh3 and .95 or 1) or (paper and .84 or arcade and .075 or (gh3 and .07 or .018))
                local rowG=selected and (gh3 and .72 or .82) or (paper and .82 or arcade and .025 or (gh3 and .022 or .055))
                local rowB=selected and (gh3 and .14 or .12) or (paper and .71 or arcade and .11 or (gh3 and .028 or .095))
                self:drawRect(listX,y,listW,rowH-2,paper and .3 or .95,rowR,rowG,rowB)
                local ink=selected or paper
                local titleR,titleG,titleB=ink and .07 or (gh3 and .96 or .82),ink and .08 or (gh3 and .90 or .88),ink and .10 or (gh3 and .78 or 1)
                if L.sort==2 and (L.scroll+display==1 or L.rows[L.scroll+display-1].artist~=row.artist) then
                    self:drawRect(listX,y,listW,smallH,.9,gh3 and .38 or .03,gh3 and .07 or .29,gh3 and .06 or .36)
                    local g=L.groups[row.artist];self:drawText(clip(row.artist,28)..' / '..g.count..' / '..g.completed..' COMPLETE',listX+36,y,gh3 and 1 or .7,gh3 and .84 or .95,gh3 and .42 or 1,1,UIFont.Small)
                end
                if selected then
                    self:drawRect(listX,y,5,rowH-2,1,gh3 and .82 or 1,gh3 and .10 or .43,gh3 and .10 or .06)
                    local pulse=.12+.10*math.sin(B.now()/160);self:drawRect(listX,y,listW,2,pulse,1,1,1)
                    self:drawRect(listX,y+rowH-4,listW,2,.85,gh3 and .82 or .20,gh3 and .12 or .73,gh3 and .10 or 1)
                    if gh3 then
                        for fi=1,5 do
                            local fc=ghFrets[fi]
                            self:drawRect(listX+36+(fi-1)*18,y+rowH-7,14,3,1,fc[1],fc[2],fc[3])
                        end
                    end
                end
                self:drawTextCentre(L.isFavorite(row.id) and '*' or tostring(L.scroll+display),listX+18,y+(rowH-mediumH)/2,ink and .42 or 1,ink and .12 or .79,ink and .05 or .28,1,UIFont.Medium)
                local limit=math.max(8,math.floor((listW-200)/10))
                local group=L.sort==2 and (L.scroll+display==1 or L.rows[L.scroll+display-1].artist~=row.artist)
                local titleY=y+(group and smallH or 5)
                self:drawText(clip(row.title,limit),listX+36,titleY,titleR,titleG,titleB,1,titleFont)
                if not group then self:drawText(clip(row.artist,limit+6),listX+36,y+5+mediumH,ink and .16 or (gh3 and .82 or .47),ink and .22 or (gh3 and .56 or .67),ink and .28 or (gh3 and .38 or .80),1,UIFont.Small) end
                self:drawTextCentre(L.duration(row.duration),durationX,y+(rowH-smallH)/2,ink and .1 or (gh3 and .90 or .76),ink and .18 or (gh3 and .82 or .85),ink and .24 or (gh3 and .72 or .93),1,UIFont.Small)
                local best=L.best(row.id,kind,difficulty)
                if paper and best and self.drawLine2 then
                    self:drawLine2(listX+8,y+rowH-14,listX+14,y+rowH-8,1,.7,.08,.13)
                    self:drawLine2(listX+14,y+rowH-8,listX+26,y+rowH-25,1,.7,.08,.13)
                end
                local allows=B.songAllowsKind(B.song(row.id),kind)
                local playableNow=L.playable(row.id,kind,difficulty)
                local badge=not allows and 'WRONG INST' or (not playableNow and (row.requiresMod and 'MOD OFF' or 'NO CHART') or best and (paper and 'OK ' or '')..string.rep('*',best.stars) or '--')
                local br,bg,bb=ink and .45 or 1,ink and .12 or .81,ink and .16 or .35
                if not allows and not selected then br,bg,bb=.92,.36,.28 elseif not playableNow and not selected then br,bg,bb=.72,.52,.36 end
                self:drawTextCentre(badge,bestX,y+(rowH-smallH)/2,br,bg,bb,1,UIFont.Small)
            end
        end
        if #L.rows==0 then
            self:drawTextCentre('NO SONGS FOUND',listX+listW/2,top+75,.82,.9,1,1,UIFont.Medium)
            self:drawTextCentre('Change the collection or clear your search.',listX+listW/2,top+108,.50,.69,.82,1,UIFont.Small)
        end
        self:drawText(#L.rows..' RESULTS  /  '..L.sorts[L.sort],listX,footer-smallH-12,paper and .12 or (gh3 and .86 or .42),paper and .25 or (gh3 and .64 or .67),paper and .34 or (gh3 and .28 or .83),1,UIFont.Small)
        if #L.rows>L.pageSize then
            local trackH=self.libraryRect.h;local thumbH=math.max(20,trackH*L.pageSize/#L.rows)
            local thumbY=top+(trackH-thumbH)*L.scroll/math.max(1,#L.rows-L.pageSize)
            self:drawRect(listX+listW-4,top,4,trackH,1,gh3 and .18 or .04,gh3 and .05 or .12,gh3 and .05 or .19)
            self:drawRect(listX+listW-4,thumbY,4,thumbH,1,gh3 and .96 or .16,gh3 and .68 or .65,gh3 and .18 or .91)
        end
        self:drawRect(right,100,panelW,footer-108,.93,paper and .87 or (gh3 and .055 or .025),paper and .85 or (gh3 and .018 or .075),paper and .75 or (gh3 and .024 or .12))
        if gh3 then self:drawRectBorder(right,100,panelW,footer-108,1,.78,.54,.16) end
        if paper then
            self:drawRect(right+23,100,1,footer-108,.65,.94,.32,.41)
            for y=142,footer-20,22 do self:drawRect(right+6,y,panelW-12,1,.28,.25,.45,.64) end
            for y=144,footer-16,52 do self:drawRect(right+6,y,7,7,1,.08,.14,.20) end
        end
        if L.selected then
            local row=L.catalog(L.selected);local compact=h<660;local size=math.min(panelW-64,compact and 82 or h>800 and 220 or 150)
            local x=right+(panelW-size)/2;local y=140
            self.artCache=self.artCache or {};local texture=self.artCache[row.cover]
            if texture==nil then texture=getTexture and getTexture(row.cover) or false;self.artCache[row.cover]=texture end
            self:drawRect(x-4,y-4,size+8,size+8,1,gh3 and .72 or .09,gh3 and .50 or .12,gh3 and .16 or .19)
            if texture then self:drawTextureScaled(texture,x,y,size,size,1,1,1,1)
            else self:drawRect(x,y,size,size,1,gh3 and .22 or .04,gh3 and .04 or .18,gh3 and .05 or .29);self:drawTextCentre('ZOMB-BAND',x+size/2,y+size/2-10,1,.8,.4,1,UIFont.Medium) end
            y=y+size+12
            local lineIndex=0;self.detailCapacity=math.max(1,math.floor((footer-78-y)/(smallH+3)))
            local function line(text,bold)
                lineIndex=lineIndex+1;if lineIndex<=(self.detailScroll or 0) then return end
                if y+(bold and mediumH or smallH)>footer-78 then return end
                self:drawText(clip(text,math.max(15,math.floor((panelW-(paper and 48 or 32))/(bold and 11 or 8)))),right+(paper and 32 or 16),y,paper and .09 or (bold and gh3 and 1 or .78),paper and .16 or (bold and gh3 and .82 or .88),paper and .24 or (bold and gh3 and .34 or .96),1,bold and UIFont.Medium or UIFont.Small)
                y=y+(bold and mediumH or smallH)+3
            end
            line(row.title,true)
            local page=self.detailPage or 1
            if page==1 then
                line(row.artist..(row.learned and ' [LEARNED]' or ''));line(row.album);line('Year: '..row.year..' / '..row.genre)
                line(L.duration(row.duration)..' / '..(row.bpm>0 and string.format('%.0f',row.bpm)..' BPM' or 'Tempo not analyzed'))
                line('Song Band: '..B.allowedInstrumentLabel(B.song(row.id),6))
                line(B.difficulty(difficulty).name..' / '..L.part(row.id,kind,difficulty))
                local sgOk=B.songAllowsKind(B.song(row.id),kind)
                local soundOk=B.isSoundAvailable(B.song(row.id))
                line((not soundOk and ('Enable mod: '..tostring(row.requiresMod or 'NewMusic'))) or (not sgOk and 'Switch to an instrument in Song Band') or (L.playable(row.id,kind,difficulty) and 'Instrument rhythm synchronized' or 'NO CHART - cannot play'))
            elseif page==2 then
                local allowedList=B.allowedInstrumentList(B.song(row.id))
                local seen={}
                line('INCLUDED IN SONG ('..#allowedList..'):')
                for _,part in ipairs(allowedList) do
                    seen[part]=true
                    line(' * '..(B.kindNames[part] or part)..': '..L.part(row.id,part,difficulty))
                end
                if kind and not seen[kind] then
                    line(' x '..(B.kindNames[kind] or kind)..': NOT IN THIS SONG')
                end
                line('Sound Group restricts band to listed parts.')
            elseif page==3 then
                local best=L.best(row.id,kind,difficulty)
                line(B.kindNames[kind]..' / '..B.difficulty(difficulty).name)
                line('BEST: '..(best and best.score or '--'));line('NOTES HIT: '..(best and best.accuracy..'%' or '--'))
                line('STARS: '..(best and string.rep('*',best.stars) or '--'));line('STREAK: '..(best and best.maxCombo or '--'))
                line('PLAYS: '..(L.profile().attempts[L.key(row.id)] or 0))
            else
                if s then for _,m in ipairs(s.members) do
                    local okInst=B.songAllowsKind(B.song(s.song),m.kind)
                    line(m.name..' / '..(B.kindNames[m.kind] or m.kind)..(okInst and '' or ' [SWITCH INST]'))
                    line('  '..B.difficulty(m.difficulty).name..' / '..(okInst and (m.ready and 'READY' or 'SYNCING') or 'NOT IN SONG'))
                end end
                local queue=s and s.setlist or L.queue;line('NEXT UP: '..#queue)
                for i=1,math.min(8,#queue) do line(i..'. '..B.song(queue[i]).name) end
            end
            self.detailLines=lineIndex
        end
        self:drawRect(14,footer-4,w-28,1,1,gh3 and .82 or .13,gh3 and .56 or .40,gh3 and .16 or .59)
        self:drawTextCentre(tostring(C.calibration)..' ms',right+70,footer+56,.7,.83,.92,1,UIFont.Small)
        if not s then
            local nearby=C.nearby();local signature=''
            for _,band in ipairs(nearby) do signature=signature..band.id..':'..#band.members..':'..tostring(band.song)..';' end
            if self.bandSignature~=signature then self.bandSignature=signature;self.bandBox:clear();self.bandIds={}
                for i,band in ipairs(nearby) do
                    self.bandIds[i]=band.id
                    local bSong=B.song(band.song)
                    self.bandBox:addOption(band.members[1].name..' - '..tostring(bSong.name)..' ('..#band.members..'/'..B.maxPlayers..') ['..B.allowedInstrumentLabel(bSong,3)..']')
                end
                if #nearby==0 then self.bandBox:addOption('No nearby waiting bands') end
                self.bandBox.selected=1
            end
        else
            local text=C.startWhenReady and s.phase=='lobby' and ('PREPARING '..C.preparedCount(s)..'/'..#s.members..' SYNCED') or s.phase=='results' and 'SET COMPLETE - browse your next song' or ('BAND '..#s.members..'/6 / '..(host and 'YOU LEAD' or 'LEADER SELECTS THE TRACK'))
            self:drawText(text,22,footer+54,.6,.85,.96,1,UIFont.Small)
            if not host then self:drawText(clip('BAND TRACK: '..B.song(s.song).name..' ('..B.allowedInstrumentLabel(B.song(s.song),4)..')',70),listX,80,1,.8,.38,1,UIFont.Small) end
        end
        local status=C.audioError or C.status
        self:drawText(clip(status,math.floor((w-44)/7)),22,h-24,C.audioError and 1 or .47,C.audioError and .34 or .66,C.audioError and .27 or .8,1,UIFont.Small)
        if not s or host then
            self:drawText(listW<500 and 'UP/DOWN SELECT / ENTER PLAY' or 'UP/DOWN  SELECT    ENTER  PLAY    SPACE  FAVORITE    P  PREVIEW',listX,80,paper and .10 or .43,paper and .23 or .68,paper and .32 or .84,1,UIFont.Small)
        end
    end
    function UI:libraryKey(key)
        if self.searchEntry:isFocused() or self.playlistName:isFocused() then
            if key==1 or key==28 then self.searchEntry:unfocus();self.playlistName:unfocus();return true end
            return false
        end
        if key==200 then L.move(-1,C)
        elseif key==208 then L.move(1,C)
        elseif key==201 then L.move(-(L.pageSize or 6),C)
        elseif key==209 then L.move(L.pageSize or 6,C)
        elseif key==199 then L.move(-#L.rows,C)
        elseif key==207 then L.move(#L.rows,C)
        elseif key==19 then L.random(C)
        elseif key==16 then L.addQueue(L.selected)
        elseif key==15 then L.cycleStyle()
        elseif key==38 then self.detailPage=(self.detailPage or 1)%4+1
        elseif key==31 then L.savePlaylist(self.playlistName:getText())
        elseif key==24 then L.loadPlaylist(self.playlistName:getText())
        elseif key==57 then self:favoriteSong()
        elseif key==25 then self:previewSong()
        elseif key==28 then if L.selected then L.select(L.selected,C);self:play() end
        elseif key==1 then self:exitBand()
        else return false end
        return true
    end
    function UI:onJoypadDirUp() if C.isPlaying(C.getSession()) then return end;L.move(-1,C) end
    function UI:onJoypadDirDown() if C.isPlaying(C.getSession()) then return end;L.move(1,C) end
    function UI:onJoypadDirLeft() L.move(-(L.pageSize or 6),C) end
    function UI:onJoypadDirRight() L.move(L.pageSize or 6,C) end
    function UI:onJoypadDown(button)
        if not Joypad then return end
        local band=C.getSession()
        if band and (band.phase=='playing' or band.phase=='countdown') then
            local lanes={[Joypad.AButton]=1,[Joypad.BButton]=2,[Joypad.XButton]=3,[Joypad.YButton]=4}
            if lanes[button] then C.hit(lanes[button]) end;return
        end
        if button==Joypad.AButton then local band=C.getSession();if not band or band.host==C.selfKey() then self:play() end
        elseif button==Joypad.BButton then self:exitBand()
        elseif button==Joypad.XButton then self:favoriteSong()
        elseif button==Joypad.YButton then self:previewSong()
        elseif button==Joypad.LBumper then self:cycleSort()
        elseif button==Joypad.RBumper then self.detailPage=(self.detailPage or 1)%4+1 end
    end
    function UI:onMouseDown(x,y)
        local s=C.getSession();if s and (s.phase=='playing' or s.phase=='countdown') then return true end
        local r=self.libraryRect
        if r and x>=r.x and x<r.x+r.w and y>=r.y and y<r.y+r.h then
            self.searchEntry:unfocus();self.playlistName:unfocus()
            local index=L.scroll+math.floor((y-r.y)/r.rowH)+1
            if L.rows[index] then L.select(L.rows[index].id,C) end
            return true
        end
        return true
    end
    function UI:onMouseWheel(delta)
        local s=C.getSession();if s and (s.phase=='playing' or s.phase=='countdown') then return true end
        if not self.libraryRect then return false end
        if self.getMouseX and self:getMouseX()>self.libraryRect.x+self.libraryRect.w then
            self.detailScroll=math.max(0,math.min(math.max(0,(self.detailLines or 0)-(self.detailCapacity or 1)),(self.detailScroll or 0)+(delta>0 and -1 or 1)*3));return true
        end
        L.scroll=math.max(0,math.min(math.max(0,#L.rows-L.pageSize),L.scroll+(delta>0 and -1 or 1)*3))
        -- Scroll browsing must not pull back to the previously selected row.
        local visible=L.rows[L.scroll+1];if visible then L.select(visible.id,C) end
        return true
    end
end
