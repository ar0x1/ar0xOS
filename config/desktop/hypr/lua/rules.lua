-- /etc/skel/.config/hypr/lua/rules.lua
-- Window / layer rules. Named rules are easier to debug with hyprctl.
-- Opacity syntax is a quoted string, NOT a Lua table (Lua config requirement).
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

-- Transparent terminals are a hacker-vibe staple, but only for the apps that
-- actually support a real alpha channel. Kitty is one of them.
hl.window_rule({
    name    = "kitty-transparency",
    match   = { class = "^(kitty)$" },
    opacity = "0.94 override 0.88 override 1.0 override",
})

-- Thunar floats and is centred so it does not tile into a 200px column.
hl.window_rule({
    name  = "thunar-float",
    match = { class = "^(Thunar)$" },
    float = true,
    move  = "20 monitor_h-120",
})

-- Polkit agent and wofi are layer surfaces; do not animate them.
hl.layer_rule({
    name    = "no-anim-overlay",
    match   = { namespace = "^(wofi|polkit-gnome)$" },
    no_anim = true,
})
