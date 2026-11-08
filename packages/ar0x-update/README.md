# ar0x-update — Phase 8 package

`/usr/bin/ar0x-update` · `arch=('any')` · **refuses bare root**.

| Mode | Root? | Network? | What it does |
|---|---|---|---|
| `--check` (default) | no | yes | assert `[ar0x] SigLevel=Required`, isolated `pacman -Sy` verifies `ar0x.db.sig`, then a temporary-dbpath `-Qu` lists pending updates |
| `--verify-repo` | no | yes | only the signature/metadata gate |
| `--rollback` | no | no | parse `/var/log/pacman.log` for old versions + cached tarballs |
| `--status` | no | no | print effective config + binary map |
| `--upgrade` | ⚠️ via `pkexec` | yes | ONE `pacman -Syu`, interactive `yes` required |
| `--self-test` | no | no | 9 stubbed unit checks, no pacman |

Config: `/etc/ar0x/update.conf` (declared `backup=()`). Full tradeoff table in
`/home/user/ar0xOS/docs/TOOLS_GUIDE.md §4`.

⚠️ `check_updates()` inlines the `checkupdates` algorithm (temporary `--dbpath`
+ symlink to the real `local` db + `fakeroot pacman -Sy`). It NEVER touches
`/var/lib/pacman/sync`, so it cannot cause a partial upgrade.
