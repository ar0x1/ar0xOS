-- /etc/skel/.config/hypr/lua/palette.lua
-- Single source of truth for DESKTOP colours. Every #RRGGBB below is asserted
-- against config/versions.env (AR0X_VOID .. AR0X_ALERT) by
-- tools/configure-desktop.sh --check and tools/validate-versions.sh.
-- This is ADR-015 applied to the compositor: change the pin, regenerate, done.
local M = {
    void    = "#07090F",
    surface = "#11151F",
    cyan    = "#00E5FF",
    magenta = "#FF2E88",
    lime    = "#A8FF60",
    text    = "#D7E0EE",
    muted   = "#6B7891",
    alert   = "#FF5C57",
}

-- Hyprland's border/shadow options want 0xRRGGBBAA strings (or an integer for
-- decoration.shadow.color). Keep those derived here, never hand-typed inline.
M.active_border   = "rgba(00e5ffee)"
M.gradient_border = "rgba(ff2e88ee)"
M.inactive_border = "rgba(6b7891aa)"
M.shadow_color    = 0xee07090f

return M
