-- /etc/skel/.config/hypr/lua/autostart.lua
-- Fires ONCE when Hyprland starts. Every command is idempotent (pgrep guard)
-- because `hyprctl reload` must not spawn a second Waybar / hyprpaper.
-- hl.exec_cmd runs outside the compositor event loop; never use a blocking
-- shell call inside a hl.bind callback (wiki: binds must not block).
hl.on("hyprland.start", function()
    -- Import the toolkit environment into the systemd USER manager and D-Bus.
    -- Without this, XDG portals and D-Bus-activated Qt/GTK apps start unstyled.
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("systemctl --user import-environment XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM GTK_THEME XCURSOR_THEME XCURSOR_SIZE")

    -- Wallpaper FIRST, so the desktop is never black behind the splash.
    hl.exec_cmd("pgrep -x hyprpaper >/dev/null || hyprpaper")
    hl.exec_cmd("pgrep -x waybar >/dev/null || waybar")
    hl.exec_cmd("pgrep -x mako >/dev/null || mako")
    hl.exec_cmd("pgrep -x nm-applet >/dev/null || nm-applet --indicator")
    hl.exec_cmd("pgrep -f polkit-gnome-authentication-agent-1 >/dev/null || /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("pgrep -x hypridle >/dev/null || hypridle")
end)
