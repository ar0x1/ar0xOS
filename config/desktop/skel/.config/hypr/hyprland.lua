-- /etc/skel/.config/hypr/hyprland.lua
-- ar0x 0.1.0 "Neon Root" — Hyprland 0.57.1 configuration ENTRY POINT.
--
-- ⚠️ Hyprland 0.57 REMOVED hyprland.conf / hyprlang. There is NO converter and
--    `hyprctl keyword` is disabled under Lua. NEVER create hyprland.conf:
--    tools/configure-desktop.sh --check and tools/validate-versions.sh both
--    fail the build if one appears anywhere in the source tree (RISK-002).
--
-- Module resolution (Hyprland 0.57): require("lua.palette") maps to
-- ./lua/palette.lua relative to THIS file, i.e. /etc/skel/.config/hypr/lua/.
-- Each require() is its own protected Lua scope, so a broken module does not
-- stop the others from loading. Order below is intentional:
--   1. shared data (palette, programs)
--   2. env BEFORE the display server starts
--   3. monitors, look & feel, animations, input
--   4. binds and rules
--   5. autostart LAST, once everything above is registered
--
-- Verify on a real host with:  Hyprland --verify-config -c /etc/skel/.config/hypr/hyprland.lua
-- Runtime errors with:         hyprctl configerrors

require("lua.palette")
require("lua.programs")

require("lua.env")
require("lua.monitors")
require("lua.looknfeel")
require("lua.animations")
require("lua.input")
require("lua.keybinds")
require("lua.rules")
require("lua.autostart")
