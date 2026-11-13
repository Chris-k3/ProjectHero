-- Vanilla hotbar gets a keep-pressed event even when a rhythm note's initial
-- key-down was consumed by the UI. Its missing keyPressedMS then causes the
-- ISHotbar.lua:808 error seen in the user's log. Scope suppression to our UI.
require 'Hotbar/ISHotbar'
HUNKBandInputGuard=HUNKBandInputGuard or {originals={},wrappers={}}
local G=HUNKBandInputGuard
function G.install()
    for _,name in ipairs({'onKeyStartPressed','onKeyPressed','onKeyKeepPressed'}) do
        local method=name
        local event=Events[({onKeyStartPressed='OnKeyStartPressed',onKeyPressed='OnKeyPressed',onKeyKeepPressed='OnKeyKeepPressed'})[name]]
        if event and ISHotbar and ISHotbar[name] then
            if not G.originals[name] then G.originals[name]=ISHotbar[name] end
            if not G.wrappers[name] then G.wrappers[name]=function(key)
                if HUNKBandClient and HUNKBandClient.window then return end
                return G.originals[method](key)
            end end
            event.Remove(ISHotbar[name]);event.Remove(G.wrappers[name])
            ISHotbar[name]=G.wrappers[name];event.Add(G.wrappers[name])
        end
    end
end
if Events.OnGameStart then Events.OnGameStart.Add(G.install) end
