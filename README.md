# kirby-restore

Disaster-recovery for the **Kirby** machine (Kali Linux). No full-OS image
backups — instead this repo holds the bootstrap script and package lists that
rebuild the system from scratch, while your personal data lives on Google
Drive, synced daily.

```
Fresh Kali install
      │
      │  curl bootstrap.sh | bash        ← this repo
      ▼
Packages installed ──► configs pulled ──► data synced
      (state/*.txt)       (Drive)          (Drive)
```

## How the backup works

### 1. Personal data — synced daily to Drive

`~/bin/data-sync.sh` runs every day at 04:00 (cron: `/etc/cron.d/kirby-backups`)
and one-way-syncs to `mydrive:data/Kirby/`:

| Local | Drive |
|-------|-------|
| `~/projects` | `data/Kirby/projects/` |
| `~/osiris` | `data/Kirby/osiris/` |
| `~/audio-mashup` | `data/Kirby/audio-mashup/` |
| `~/bin` | `data/Kirby/bin/` |
| `~/Documents` | `data/Kirby/Documents/` |
| `~/data` (OpenViking KB: collections, vectordb, skills) | `data/Kirby/openviking-data/` |
| `~/.openviking` (OpenViking config) | `data/Kirby/dot-openviking/` |
| `~/.config` | `data/Kirby/dot-config/` |
| `~/.hermes` | `data/Kirby/dot-hermes/` |
| `~/.ssh` | `data/Kirby/dot-ssh/` |
| `crontab -l` | `data/Kirby/crontab/ahard.crontab.txt` |
| `/mnt/ssd/projects` | `data/Kirby/ssd-projects/` |

Build junk (`node_modules`, `dist`, `build`, venvs, `__pycache__`) is excluded.
The OpenViking server venv (`~/.openviking-env`, ~1.3G) is not synced — its
package list is captured monthly (`state/openviking-venv-pip.txt`) and the
bootstrap rebuilds it.

### 2. System state — archived monthly to Drive

`~/bin/system-state-capture.sh` runs on the 1st at 05:00 and uploads a small
(~61 MB) archive to `mydrive:backups/Kirby/monthly/YYYY-MM/`:

- package lists — `apt-mark showmanual`, full dpkg list, pipx, npm -g, flatpak
- `/etc` (fstab, lightdm, network, X11, cron.d, …)
- `/usr/local/{bin,sbin}` and `~/bin`
- crontabs, custom systemd units (system + user), enabled-units list
- disk layout — sfdisk dumps, lsblk, blkid, EFI listing, df
- desktop settings (dconf dump), users/groups

The same job also refreshes `state/` in this repo and pushes, so the package
lists here are always current. **24 monthly archives are kept**, older ones
auto-pruned.

### 3. Health check

`~/bin/backup-heartbeat.sh` runs daily at 09:00
(cron: `/etc/cron.d/backup-heartbeat`), verifies the last sync/archive, Drive
reachability, and cron entries. Log: `/var/log/backup-heartbeat.log`.

### What is deliberately NOT backed up

LLM models and backends (~27G), `~/Downloads`, caches, `~/.local`, Steam
games, Docker container volumes (compose files *are* in the monthly archive
via `/etc` + `/opt` paths captured in `~/bin` scripts) — all re-downloadable
or rebuildable.

> **Note:** `~/.ssh` private keys go to Drive. Accepted tradeoff — it's a
> private account, and a restore without them is painful.

---

## Restore: step by step

### 1. Install Kali fresh

Standard install, create your user, log in to a terminal. Internet required.

### 2. Run the bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/ahardy11397/kirby-restore/main/bootstrap.sh | bash
```

This does, in order:

1. **Packages** — installs rclone/git/curl/zstd, then all ~1,450 packages from
   `state/apt-manual.txt` (takes a while).
2. **Drive auth** — it pauses; run `rclone config reconnect mydrive` when it
   prompts, a browser opens, authorize, come back, press Enter.
3. **Data + configs down from Drive** — syncs everything in the table above
   back into place (`~/projects`, `~/.config`, `~/.ssh`, …) and unpacks the
   newest monthly state archive to `~/restore-work/unpacked/`.
4. **Crontab + user systemd units** restored automatically.

### 3. Follow the printed manual checklist

The bootstrap ends with the short list of things that need a human:

- [ ] Merge `/etc` carefully: `sudo cp -a ~/restore-work/unpacked/etc/* /etc/`
      (review first — host-specific bits like machine-id may need care)
- [ ] Custom system units/timers: copy from
      `~/restore-work/unpacked/systemd/`, then `sudo systemctl daemon-reload`
      and `sudo systemctl enable --now <unit>`
- [ ] Mount `/mnt/ssd` (fstab copy is in the state archive) before syncing
      `ssd-projects` if you skipped it in step 2's prompts
- [ ] `gh auth login` (GitHub CLI)
- [ ] Re-download models/backends/games as needed
- [ ] Verify the loop works: `bash ~/bin/data-sync.sh` and
      `bash ~/bin/system-state-capture.sh`

### 4. Reinstall the bootloader if replacing the disk

The partition layout dump is in the state archive
(`partition-layout.<dev>.dump`): boot a live USB, `sfdisk /dev/nvme0n1 < dump`,
format, extract the archive (or re-run bootstrap onto the mounted fs),
`grub-install /dev/nvme0n1 && update-grub`.

---

## Maintaining this repo

- **Automatic:** each monthly capture commits fresh `state/*.txt` lists.
- **Manual:** edit `bootstrap.sh` in `~/bin/bootstrap.sh` (canonical copy) —
  the capture job copies it here each month, or push sooner by hand:

```bash
cd ~/kirby-restore && cp ~/bin/bootstrap.sh . && git add -A && git commit -m "update bootstrap" && git push
```

## Known sharp edge

rclone's shared Google Drive `client_id` is being retired during 2026. When
that happens **all** Drive access stops (backups *and* the vault bisync) until
you create your own client_id: https://rclone.org/drive/#making-your-own-client-id
