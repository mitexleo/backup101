#!/bin/bash

# Variables
DOCKER_VOLUMES_DIR="/var/lib/docker/volumes"
ROOT_HOME_DIR="/root"
BACKUP_DIR="/root/backups"
B2_BUCKET="backup101"
MAX_BACKUPS=7  # Number of backups to keep
BACKUP_COUNT_FILE="/root/backup_count.txt"
RUNNING_CONTAINERS_FILE="/tmp/running_containers.txt"
LOG_FILE="/var/log/docker_backup.log"
TMP_DIR="/root/tmp"

# Ensure the backup directory exists
mkdir -p "$BACKUP_DIR"

# Initialize backup counts
declare -A BACKUP_COUNT

# Load existing backup counts from the backup_count.txt file if it exists
if [ -f "$BACKUP_COUNT_FILE" ]; then
    while IFS= read -r line; do
        IFS=' ' read -r key count <<< "$line"
        BACKUP_COUNT["$key"]="$count"
    done < "$BACKUP_COUNT_FILE"
fi

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Save the list of running containers
log_message "Saving the list of running containers..."
docker ps -q > "$RUNNING_CONTAINERS_FILE"
if [ $? -ne 0 ]; then
    log_message "Failed to save the list of running containers."
    exit 1
fi

# Stop all running Docker containers
log_message "Stopping all running Docker containers..."
RUNNING_CONTAINERS=$(docker ps -q)
if [ -n "$RUNNING_CONTAINERS" ]; then
    docker stop $RUNNING_CONTAINERS
else
    log_message "No running containers to stop."
fi

# Create backups
log_message "Creating backup archives..."
BACKUP_TIMESTAMP=$(date '+%Y%m%d%H%M%S')
DOCKER_BACKUP_NAME="docker_volumes_$BACKUP_TIMESTAMP.tar.gz"
ROOT_BACKUP_NAME="root_home_$BACKUP_TIMESTAMP.tar.gz"

tar -czf "$BACKUP_DIR/$DOCKER_BACKUP_NAME" "$DOCKER_VOLUMES_DIR"
if [ $? -ne 0 ]; then
    log_message "Failed to create Docker volumes backup."
    exit 1
fi

tar -czf "$BACKUP_DIR/$ROOT_BACKUP_NAME" "$ROOT_HOME_DIR"
if [ $? -ne 0 ]; then
    log_message "Failed to create root home backup."
    exit 1
fi

# Upload backups to Backblaze B2
log_message "Uploading backups to Backblaze B2..."
b2 upload-file --noProgress "$B2_BUCKET" "$BACKUP_DIR/$DOCKER_BACKUP_NAME" "$DOCKER_BACKUP_NAME"
if [ $? -ne 0 ]; then
    log_message "Failed to upload Docker volumes backup to Backblaze B2."
    exit 1
fi

b2 upload-file --noProgress "$B2_BUCKET" "$BACKUP_DIR/$ROOT_BACKUP_NAME" "$ROOT_BACKUP_NAME"
if [ $? -ne 0 ]; then
    log_message "Failed to upload root home backup to Backblaze B2."
    exit 1
fi

# Update and manage backup retention
log_message "Managing backup retention..."
BACKUP_COUNT["docker_volumes"]=$(( ${BACKUP_COUNT["docker_volumes"]:-0} + 1 ))
BACKUP_COUNT["root_home"]=$(( ${BACKUP_COUNT["root_home"]:-0} + 1 ))

for key in "docker_volumes" "root_home"; do
    if [ "${BACKUP_COUNT["$key"]}" -gt "$MAX_BACKUPS" ]; then
        OLDEST_BACKUP_NUMBER=$(( BACKUP_COUNT["$key"] - MAX_BACKUPS ))
        OLDEST_BACKUP_NAME="${key}_$(date -d "-$OLDEST_BACKUP_NUMBER days" '+%Y%m%d%H%M%S').tar.gz"

        log_message "Deleting old backup: $OLDEST_BACKUP_NAME"
        b2 delete-file-version "$B2_BUCKET" "$OLDEST_BACKUP_NAME"
        if [ $? -eq 0 ]; then
            log_message "Successfully deleted old backup: $OLDEST_BACKUP_NAME"
        else
            log_message "Failed to delete old backup: $OLDEST_BACKUP_NAME"
        fi
    fi
done

# Remove local backup files
log_message "Deleting local backup files..."
rm -f "$BACKUP_DIR/$DOCKER_BACKUP_NAME" "$BACKUP_DIR/$ROOT_BACKUP_NAME"

# Save updated backup counts to the backup_count.txt file
log_message "Saving updated backup counts..."
{
    for key in "${!BACKUP_COUNT[@]}"; do
        echo "$key ${BACKUP_COUNT[$key]}"
    done
} > "$BACKUP_COUNT_FILE"

# Restart previously running containers
log_message "Restarting previously running containers..."
while IFS= read -r container_id; do
    docker start "$container_id"
    if [ $? -ne 0 ]; then
        log_message "Failed to restart container: $container_id"
    else
        log_message "Successfully restarted container: $container_id"
    fi
done < "$RUNNING_CONTAINERS_FILE"

# Clean up temporary file
rm -f "$RUNNING_CONTAINERS_FILE"

log_message "Backup process completed successfully."
