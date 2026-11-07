-- /etc/skel/.config/hypr/lua/monitors.lua
-- A single wildcard rule: "preferred" + "auto" means every attached output
-- uses its native mode, is positioned automatically and gets an automatic
-- scale. This is the portable choice for a LIVE ISO that must boot on laptops,
-- desktops, VMs and QEMU without a per-machine monitor file.
--
-- Tradeoff: on a mixed-DPI multi-monitor setup "auto" can pick fractional
-- scaling per output. Users who need exact control should copy this file to
-- ~/.config/hypr/lua/monitors.lua and replace output="" with e.g. "DP-1",
-- mode="2560x1440@144", position="0x0", scale=1.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})
