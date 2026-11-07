-- /etc/skel/.config/hypr/lua/env.lua
-- hl.env() sets variables BEFORE the Wayland display server initialises.
--
-- ⚠️ GDK_BACKEND is deliberately NOT set here OR in /etc/environment.d.
--    Phase 5 made that decision: forcing GDK_BACKEND=wayland globally breaks
--    GTK applications that must run under XWayland. Hyprland exports the
--    correct session variables itself. tools/configure-desktop.sh --check
--    fails if anyone reintroduces a global GDK_BACKEND.
--
-- QT_QPA_PLATFORMTHEME uses a COLON-separated list (ArchWiki, Qt):
-- Qt5 apps resolve qt5ct, Qt6 apps resolve qt6ct, from ONE variable.
-- QT_QPA_PLATFORM uses a SEMICOLON-separated list (Qt platform plugin list).
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct:qt6ct")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Cursor: Adwaita is the PLACEHOLDER shipped by Arch's adwaita-cursors.
-- Phase 7 replaces this with the ar0x hyprcursor theme (RISK-040).
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- GTK3 picks up Adwaita-dark from settings.ini; GTK4/libadwaita needs BOTH
-- this variable AND ~/.config/gtk-4.0/gtk.css @define-color overrides.
-- GTK_THEME is one of the very few levers libadwaita still honours.
hl.env("GTK_THEME", "Adwaita-dark")
