#!/bin/bash
# ==============================================================================
# Kirby bootstrap — rebuild a fresh Kali install into your system
#
# Run on a fresh Kali install as your normal user (sudo when needed):
#
#   curl -fsSL https://raw.githubusercontent.com/ahardy11397/kirby-restore/main/bootstrap.sh | bash
#
# What it does:
#   1. Installs rclone + git, then all your packages from the captured list
#   2. Sets up rclone auth for Google Drive (interactive, once)
#   3. Pulls your configs down from Drive (/etc, dotfiles, bin, ssh)
#   4. Restores crontab, enables your custom systemd units
#   5. Prints what's left to do by hand
#
# Package lists + repo updated monthly by /home/ahard/bin/system-state-capture.sh
# ==============================================================================

set -u
REPO_RAW="https://raw.githubusercontent.com/ahardy11397/kirby-restore/main"
BRANCH="${REPO_RAW##*/}"

step() { echo; echo "==> $1"; }

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user (it will sudo when needed)."; exit 1
fi

# ------------------------------------------------------------------------------
step "1/5 Base tools + package restore"
sudo apt-get update -y
sudo apt-get install -y rclone git curl zstd

curl -fsSL "${REPO_RAW}/state/apt-manual.txt" -o /tmp/apt-manual.txt
if [[ -s /tmp/apt-manual.txt ]]; then
  echo "Installing $(wc -l < /tmp/apt-manual.txt) manually-installed packages (this takes a while)..."
  sudo apt-get install -y $(cat /tmp/apt-manual.txt) || echo "WARN: some packages failed — check output above"
else
  echo "WARN: could not fetch apt-manual.txt — install packages by hand"
fi

# ------------------------------------------------------------------------------
step "2/5 Google Drive auth (browser opens once)"
rclone config create mydrive drive 2>/dev/null || true
echo "Now authorize Drive: run this, follow the prompts, then come back:"
echo "    rclone config reconnect mydrive"
echo "Press Enter when done..."
read -r

# ------------------------------------------------------------------------------
step "3/5 Pull data + configs from Drive"
mkdir -p ~/restore-work
rclone copy "mydrive:backups/$(hostname)/monthly/$(date '+%Y-%m')/" ~/restore-work/ || \
  echo "WARN: no state archive for this month — pick one: rclone lsd mydrive:backups/\$(hostname)/monthly/"
LATEST=$(ls -t ~/restore-work/*-state-*.tar.zst 2>/dev/null | head -1)
if [[ -n "${LATEST:-}" ]]; then
  mkdir -p ~/restore-work/unpacked
  zstd -d "$LATEST" -o ~/restore-work/state.tar && tar -xf ~/restore-work/state.tar -C ~/restore-work/unpacked
  echo "State archive unpacked to ~/restore-work/unpacked"
fi

# personal data back into place
rclone sync "mydrive:data/Kirby/projects/"     ~/projects/      --progress
rclone sync "mydrive:data/Kirby/osiris/"       ~/osiris/        --progress || true
rclone sync "mydrive:data/Kirby/audio-mashup/" ~/audio-mashup/  --progress || true
rclone sync "mydrive:data/Kirby/bin/"          ~/bin/           --progress && chmod +x ~/bin/* 2>/dev/null
rclone sync "mydrive:data/Kirby/dot-config/"   ~/.config/       --progress
rclone sync "mydrive:data/Kirby/dot-hermes/"   ~/.hermes/       --progress || true
rclone sync "mydrive:data/Kirby/dot-ssh/"      ~/.ssh/          --progress && chmod 700 ~/.ssh && chmod 600 ~/.ssh/* 2>/dev/null
rclone sync "mydrive:data/Kirby/ssd-projects/" /mnt/ssd/projects/ --progress || echo "NOTE: mount /mnt/ssd first (fstab in state archive)"

# ------------------------------------------------------------------------------
step "4/5 Crontab + systemd units"
if [[ -f ~/restore-work/unpacked/cron/crontabs/ahard ]]; then
  crontab ~/restore-work/unpacked/cron/crontabs/ahard && echo "crontab restored"
fi
if [[ -d ~/restore-work/unpacked/systemd/user ]]; then
  mkdir -p ~/.config/systemd/user
  cp -a ~/restore-work/unpacked/systemd/user/. ~/.config/systemd/user/
  systemctl --user daemon-reload
fi
echo "System units (fstab, lightdm, cron.d): copy manually from ~/restore-work/unpacked/ —"
echo "  sudo cp -a ~/restore-work/unpacked/etc/* /etc/   # review first, merge carefully"
echo "  sudo cp ~/restore-work/unpacked/systemd/*.service /etc/systemd/system/ 2>/dev/null"
echo "  sudo cp ~/restore-work/unpacked/systemd/*.timer   /etc/systemd/system/ 2>/dev/null"
echo "  sudo systemctl daemon-reload"

# ------------------------------------------------------------------------------
step "5/5 Done — manual checklist"
cat <<'EOF'
Remaining by hand:
  [ ] /etc merge (fstab, lightdm, X11, cron.d) — from ~/restore-work/unpacked/etc
  [ ] sudo systemctl enable --now <your custom timers: data-sync, drive-sync, heartbeat...>
  [ ] gh CLI auth:  gh auth login
  [ ] LLM server / models: re-download (not backed up, by design)
  [ ] Steam: re-download games (not backed up, by design)
  [ ] Docker: containers live in /opt/container-services — copy from old disk or re-clone
  [ ] Verify: bash ~/bin/data-sync.sh && bash ~/bin/system-state-capture.sh
EOF
echo
echo "Bootstrap complete."
