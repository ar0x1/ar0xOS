-- /etc/skel/.config/hypr/lua/looknfeel.lua
-- Cyberpunk / dark-hacker look. Every colour comes from lua/palette.lua.
-- Only keys present in Hyprland 0.57's official example/hyprland.lua are used:
-- unverified options are deliberately excluded so `Hyprland --verify-config`
-- cannot fail on a made-up key.
local c = require("lua.palette")

hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 18,
        border_size = 2,

        -- Gradient active border (cyan -> magenta) is the strongest ar0x cue.
        col = {
            active_border   = { colors = { c.active_border, c.gradient_border }, angle = 45 },
            inactive_border = c.inactive_border,
        },

        resize_on_border = false,
        allow_tearing    = false,   -- tearing needs an explicit kernel/GPU review
        layout           = "dwindle",
    },

    decoration = {
        rounding       = 6,        -- sharp-ish "terminal" corners, not bubbly
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.94,   -- slight dim: focus is obvious at a glance

        shadow = {
            enabled      = true,
            range        = 8,
            render_power = 3,
            color        = c.shadow_color,
        },

        blur = {
            enabled  = true,
            size     = 4,
            passes   = 2,          -- 2 passes is cheap; 4 halves FPS on llvmpipe
            vibrancy = 0.18,
        },
    },

    animations = { enabled = true },
})

hl.config({
    dwindle = { preserve_split = true },
    master  = { new_status = "master" },
    scrolling = { fullscreen_on_one_column = true },
})

hl.config({
    misc = {
        -- -1 = show the default wallpaper when no client is open. We ship a
        -- real ar0x wallpaper via hyprpaper, so do NOT force the mascot.
        force_default_wallpaper = -1,
        disable_hyprland_logo   = false,
    },
    layers = {
        allow_new_top_layers_over_existing_fullscreen = true,
    },
})
