-- /etc/skel/.config/hypr/lua/programs.lua
-- Shared program names. One change here updates every keybind. Only binaries
-- GUARANTEED to be in config/packages.x86_64 are referenced.
local M = {
    terminal    = "kitty",
    editor      = "nvim",
    fileManager = "thunar",
    launcher    = "wofi --show drun",
    lock        = "hyprlock",
    picker      = "hyprpicker",  -- installed by ar0x-welcome in Phase 8, optional
}
return M
