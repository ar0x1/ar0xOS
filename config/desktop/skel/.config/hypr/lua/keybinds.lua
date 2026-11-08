-- /etc/skel/.config/hypr/lua/keybinds.lua
-- Only dispatchers documented in Hyprland 0.57 example/hyprland.lua and the
-- official binds page are used. hl.dsp.* names are NOT the legacy hyprctl
-- dispatcher strings; do not "translate" them.
-- ⚠️ Keybind callbacks must never block (no io.popen / sleeps / clipboard waits).
local mainMod = "SUPER"
local p = require("lua.programs")

-- Applications
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(p.terminal))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(p.fileManager))
hl.bind(mainMod .. " + R",      hl.dsp.exec_cmd(p.launcher))
hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(p.editor))
hl.bind(mainMod .. " + L",      hl.dsp.exec_cmd(p.lock))
hl.bind(mainMod .. " + C",      hl.dsp.window.close())
hl.bind(mainMod .. " + M",      hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))

-- Window management
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P",      hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J",      hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + TAB",    function()
    hl.dispatch(hl.dsp.window.cycle_next())
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top" }))
end)

-- Focus (arrow keys)
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Workspaces 1..10 (10 is bound to key 0)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad (special workspace)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("scratch"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:scratch" }))

-- Mouse: drag / resize with SUPER held
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Screenshot: region -> clipboard (grim + slurp + wl-copy, all in packages)
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"))

-- Multimedia keys work even while hyprlock is active ({ locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),   { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
