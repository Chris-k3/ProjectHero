HUNKZombBandTestKit={
    module='HUNKZombBandTestKit',protocol=1,
    items={'Base.GuitarAcoustic','Base.Banjo','Base.GuitarElectricBass','Base.GuitarElectric',
        'Base.Flute','Base.Harmonica','Base.Keytar','Base.Saxophone','Base.Trumpet','Base.Violin',
        'Base.Drumstick','Base.Microphone','Base.ZombBand_AcousticGuitar','Base.ZombBand_ElectricGuitar',
        'Base.ZombBand_BassGuitar','Base.ZombBand_DrumKit','Base.ZombBand_MicrophoneStand'},
}
function HUNKZombBandTestKit.find(container,fullType)
    if not container then return nil end
    local items=container:getItems()
    for i=0,items:size()-1 do
        local item=items:get(i)
        if item:getFullType()==fullType then return item end
        if instanceof(item,'InventoryContainer') then
            local found=HUNKZombBandTestKit.find(item:getInventory(),fullType)
            if found then return found end
        end
    end
end
