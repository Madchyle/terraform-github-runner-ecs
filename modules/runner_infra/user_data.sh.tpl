#!/bin/bash
# user_data.sh.tpl (runner_infra)
#
# EC2 bootstrap script for the *capacity layer* (ECS container instances) used by this project.
#
# Goals:
# - Configure the ECS agent to join the target cluster (`/etc/ecs/ecs.config`).
# - Ensure Docker uses a dedicated data volume for `/var/lib/docker` (to avoid filling the root disk).
# - Start Docker (verify it is ready) and then start the ECS agent.
# - Optionally install a scheduled Docker prune (systemd timer preferred; cron fallback).
set -euo pipefail

############################################
# LOG USER-DATA OUTPUT (VERY IMPORTANT)
############################################
# Redirect all stdout/stderr to:
# - `/var/log/userdata.log` (persisted for debugging)
# - instance console (`/dev/console`) via `logger` (visible in EC2 console output)
exec > >(tee /var/log/userdata.log | logger -t userdata -s 2>/dev/console) 2>&1
echo "===== USERDATA STARTED ====="

############################################
# ECS CONFIG
############################################
# ECS agent reads `/etc/ecs/ecs.config` on startup to determine which cluster to join and which region it is running in.
# `cluster_name` and `aws_region` are Terraform template variables provided by the `runner_infra` module.
# This heredoc writes a plain-text config file consumed by the ECS agent (not executed as shell).
echo "Writing ECS config..."
cat > /etc/ecs/ecs.config <<EOF
ECS_CLUSTER=${cluster_name}
AWS_REGION=${aws_region}
EOF
echo "ECS cluster: ${cluster_name}"

############################################
# VARIABLES
############################################
# Docker data-root. We move it to a dedicated attached volume to reduce the risk of root-disk exhaustion.
# Note: `DATA_DEVICE` assumes an EBS data volume is attached and exposed to the instance as NVMe.
DOCKER_DATA_DIR="/var/lib/docker"
DATA_DEVICE="/dev/nvme1n1"

############################################
# STOP ECS & DOCKER EARLY
############################################
# Stop Docker early so it doesn't initialize `/var/lib/docker` on the root disk before we mount the data volume.
# We also disable the socket units to prevent auto-start while we're configuring storage.
echo "Stopping ECS and Docker early..."
systemctl stop  docker docker.socket || true
systemctl disable  docker docker.socket || true

############################################
# WAIT FOR DATA VOLUME
############################################
# On boot, the NVMe device may appear a few seconds after the script starts.
# Wait up to ~60 seconds for the device node to exist, then fail fast if it's missing.
echo "Waiting for Docker data volume..."
for i in {1..60}; do
  [ -e "$DATA_DEVICE" ] && break
  sleep 1
done

if [ ! -e "$DATA_DEVICE" ]; then
  echo "ERROR: Data device $DATA_DEVICE not found"
  exit 1
fi
echo "Found data device: $DATA_DEVICE"

############################################
# FORMAT IF NEEDED
############################################
# If the block device has no filesystem signature, create an ext4 filesystem.
# This is idempotent: we only format when `blkid` can't identify an existing filesystem.
if ! blkid "$DATA_DEVICE" >/dev/null 2>&1; then
  echo "Formatting $DATA_DEVICE with ext4..."
  mkfs.ext4 -F "$DATA_DEVICE"
  echo "Format complete"
else
  echo "Device already formatted, skipping format"
fi

############################################
# MOUNT DOCKER DATA DIRECTORY
############################################
# Mount the data device at Docker's data directory.
# This ensures all images/layers/containers go to the attached volume rather than the root disk.
echo "Mounting $DATA_DEVICE to $DOCKER_DATA_DIR..."
mkdir -p "$DOCKER_DATA_DIR"
mount "$DATA_DEVICE" "$DOCKER_DATA_DIR"

# Verify the mount is active; if not, bail out to avoid Docker writing to the root filesystem.
if ! mountpoint -q "$DOCKER_DATA_DIR"; then
  echo "ERROR: /var/lib/docker is not mounted"
  exit 1
fi
echo "Mount successful"
df -h "$DOCKER_DATA_DIR"

############################################
# PERSIST MOUNT
############################################
# Persist the mount across reboots using `/etc/fstab` with a UUID-based entry.
# `nofail` prevents boot failure if the device is missing (e.g., misconfiguration), but we still fail this script earlier.
echo "Adding mount to fstab..."
UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
grep -q "$UUID" /etc/fstab || \
  echo "UUID=$UUID $DOCKER_DATA_DIR ext4 defaults,nofail 0 2" >> /etc/fstab
echo "UUID: $UUID"

############################################
# FORCE DOCKER TO USE EBS VOLUME
############################################
# Configure the Docker daemon to use the mounted directory as its data-root.
# NOTE: We do not put comments inside this JSON file because JSON does not support comments.
echo "Configuring Docker data-root..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "data-root": "/var/lib/docker"
}
EOF

############################################
# START DOCKER AND WAIT UNTIL READY
############################################
# Start Docker now that storage is configured, then poll until `docker info` succeeds.
echo "Starting Docker..."
systemctl enable docker
systemctl start docker

echo "Waiting for Docker to be ready..."
for i in {1..30}; do
  docker info >/dev/null 2>&1 && break
  sleep 1
done

# Fail fast if Docker never became ready (prevents ECS tasks from launching into a broken Docker runtime).
docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker did not start"
  exit 1
}
echo "Docker is ready"
docker info | grep -E "Docker Root Dir|Server Version"

############################################
# START ECS AGENT (NON-BLOCKING)
############################################
# Start ECS agent after Docker is healthy so the instance can immediately accept placements.
# `--no-block` lets the script complete without waiting for ECS to reach steady state.
echo "Enabling and starting ECS agent..."
systemctl enable ecs
systemctl start --no-block ecs
echo "ECS agent start initiated (running in background)"

echo "===== USERDATA COMPLETED SUCCESSFULLY ====="

############################################
# OPTIONAL: DOCKER PRUNE
############################################
# Optional maintenance: scheduled pruning of unused Docker resources to keep `/var/lib/docker` from growing without bound.
# Controlled via Terraform template condition `enable_docker_prune_cron`.
%{ if enable_docker_prune_cron }
# Docker disk hygiene: prune stopped containers + unused images/networks/volumes.
# This helps prevent /var/lib/docker from filling up on long-lived ECS container instances.
cat > /usr/local/bin/ecs-docker-prune.sh << 'EOF'
#!/bin/bash
set -euo pipefail

LOG=/var/log/ecs-docker-prune.log
echo "[$(date -Is)] starting docker prune" >> "$LOG"

if ! command -v docker >/dev/null 2>&1; then
  echo "[$(date -Is)] docker not found; skipping" >> "$LOG"
  exit 0
fi

# Remove stopped/exited containers
docker container prune -f >> "$LOG" 2>&1 || true

# Only removes resources that are NOT in use.
docker system prune -af --volumes --filter "until=${docker_prune_until}" >> "$LOG" 2>&1 || true
echo "[$(date -Is)] finished docker prune" >> "$LOG"
EOF
chmod 0755 /usr/local/bin/ecs-docker-prune.sh

# Prefer systemd timer (cron isn't installed on some ECS-optimized AMIs).
if command -v systemctl >/dev/null 2>&1; then
  # Parse `docker_prune_cron_schedule` (a standard 5-field cron string) and translate it into a systemd OnCalendar where possible.
  # Convert a simple "minute hour * * *" cron schedule to systemd OnCalendar.
  # Disable glob expansion to prevent * from being expanded as filenames
  # Note: This translation intentionally supports only simple hourly/daily schedules; anything more complex defaults to `hourly`.
  set -f
  set -- ${docker_prune_cron_schedule}
  set +f
  _min="$${1:-0}"
  _hour="$${2:-*}"
  _dom="$${3:-*}"
  _mon="$${4:-*}"
  _dow="$${5:-*}"

  echo "Parsed cron: min=$_min hour=$_hour dom=$_dom mon=$_mon dow=$_dow"

  if [ "$_hour" = "*" ]; then
    # Hourly: run at specified minute every hour
    _on_calendar="*-*-* *:$(printf '%02d' "$_min"):00"
  elif [ "$_dom" = "*" ] && [ "$_mon" = "*" ] && [ "$_dow" = "*" ]; then
    # Daily at specific time
    _on_calendar="*-*-* $(printf '%02d:%02d:00' "$_hour" "$_min")"
  else
    # Default to hourly
    _on_calendar="hourly"
  fi

  echo "Creating systemd service..."
  echo "$_on_calendar"
  echo "Creating systemd timer..."
  echo "$_on_calendar"

  cat > /etc/systemd/system/ecs-docker-prune.service << 'EOF'
[Unit]
Description=ECS Docker disk hygiene (docker system prune)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ecs-docker-prune.sh
EOF

  cat > /etc/systemd/system/ecs-docker-prune.timer << EOF
[Unit]
Description=Run ECS Docker prune on schedule

[Timer]
OnCalendar=$_on_calendar
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now ecs-docker-prune.timer || true
else
  # Fallback: use cron (only works if a cron daemon exists on the AMI).
  # Fallback: install cron entry (only works if cron daemon exists on the AMI)
  cat > /etc/cron.d/ecs-docker-prune << EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${docker_prune_cron_schedule} root /usr/local/bin/ecs-docker-prune.sh
EOF
  chmod 0644 /etc/cron.d/ecs-docker-prune
fi
%{ endif }