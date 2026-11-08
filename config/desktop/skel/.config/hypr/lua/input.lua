-- /etc/skel/.config/hypr/lua/input.lua
-- Keyboard layout matches Phase 5's /etc/vconsole.conf (KEYMAP=us), so the VT
-- and the Wayland session never disagree. kb_options is empty on purpose:
-- remapping Caps Lock is a personal choice, not a distro default.
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse    = 1,
        sensitivity     = 0,        -- 0 = no pointer acceleration change
        touchpad        = { natural_scroll = false },
    },
})

-- 3-finger horizontal swipe switches workspaces (laptop-friendly).
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
