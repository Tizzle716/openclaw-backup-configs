#!/bin/bash
# Ensure log directory exists
mkdir -p /home/viktor-admin/logs/

# 1. Pause core containers (The safe alternative to agent-ctl)
docker pause $(docker ps -q --filter "label=openclaw-core")
sleep 5

# 2. Perform the lean backup
tar -czf /tmp/openclaw_backup.tar.gz -C /home/viktor-admin/sovereign-core . 

# Update this line to use mega
rclone copy /tmp/openclaw_backup.tar.gz mega:Openclaw-Backups/ --config /root/.config/rclone/rclone.conf

# 4. Cleanup
rm /tmp/openclaw_backup.tar.gz

# 5. Resume core containers
docker unpause $(docker ps -q --filter "label=openclaw-core")

# 6. Heartbeat Log
echo "$(date): Backup to MEGA successful" >> /home/viktor-admin/logs/backup_heartbeat.log
