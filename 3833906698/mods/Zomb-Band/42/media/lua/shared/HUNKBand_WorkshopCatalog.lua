-- Connects Steam Workshop NewMusic packs (EA_H, NMGreatestHits, G80s, G90s, G70s, CMM) to Zomb-Band.
local M = {}
local PACKS = {
  {modId="EA_H",workshopId="3808737141",source="Exitos del Ayer y Hoy",genre="Latin Classics / Pop",cover="media/ui/ZombBand/Pack_EA_H.png",packKey="ea_h",moduleName="HUNKBand_Pack_EA_H"},
  {modId="NMGreatestHits",workshopId="3751364201",source="New Music Greatest Hits",genre="Greatest Hits",cover="media/ui/ZombBand/Pack_NMGreatestHits.png",packKey="greatest_hits",moduleName="HUNKBand_Pack_NMGreatestHits"},
  {modId="NewMusicG80s",workshopId="3765079521",source="Graves 80s Mixtape",genre="80s Mixtape",cover="media/ui/ZombBand/Pack_NewMusicG80s.png",packKey="g80s",moduleName="HUNKBand_Pack_NewMusicG80s"},
  {modId="NewMusicG90s",workshopId="3765670104",source="Graves 90s Mixtape",genre="90s Mixtape",cover="media/ui/ZombBand/Pack_NewMusicG90s.png",packKey="g90s",moduleName="HUNKBand_Pack_NewMusicG90s"},
  {modId="NewMusicG70s",workshopId="3765077081",source="Graves 70s Mixtape",genre="70s Mixtape",cover="media/ui/ZombBand/Pack_NewMusicG70s.png",packKey="g70s",moduleName="HUNKBand_Pack_NewMusicG70s"},
  {modId="NewMusic_CMM",workshopId="3760471726",source="Classical Music Mix",genre="Classical",cover="media/ui/ZombBand/Pack_NewMusic_CMM.png",packKey="cmm",moduleName="HUNKBand_Pack_NewMusic_CMM"},
}
function M.appendTo(B)
    if type(B) ~= 'table' or type(B.songs) ~= 'table' then return end
    B.workshopPacks = B.workshopPacks or {}
    local baseCount = #B.songs
    for _, p in ipairs(PACKS) do
        local ok, entries = pcall(require, p.moduleName)
        if ok and type(entries) == 'table' then
            local loadedCount = 0
            for _, e in ipairs(entries) do
                if type(e) == 'table' and e.n and e.s and e.d and e.d > 0 then
                    loadedCount = loadedCount + 1
                    B.songs[#B.songs + 1] = {
                        name = e.n,
                        artist = e.a,
                        album = e.al,
                        uid = e.u,
                        sound = e.s,
                        soundAlt = p.modId .. '.' .. e.s,
                        origin = 'workshop',
                        requiresMod = p.modId,
                        workshopId = p.workshopId,
                        packKey = p.packKey,
                        source = p.source,
                        genre = p.genre,
                        cover = p.cover,
                        bpm = e.b or 120,
                        durationMs = e.d,
                        hitSounds = false,
                        chartLanes = 4,
                        allowedInstruments = e.inst,
                        rawCharts = e.ch,
                    }
                end
            end
            B.workshopPacks[p.modId] = { title = p.source, workshopId = p.workshopId, count = loadedCount, packKey = p.packKey }
        end
    end
    return #B.songs - baseCount
end
return M
