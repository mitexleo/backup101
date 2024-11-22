#!/bin/bash

set -e  # Exit on any error

# Variables
export PATH=$PATH:/root/.local/bin  # Ensure 'b2' is in PATH
DOCKER_VOLUMES_DIR="/var/lib/docker/volumes"
ROOT_HOME_DIR="/root"
BACKUP_DIR="/mnt/backups"
B2_BUCKET="backup101"
MAX_BACKUPS=7
BACKUP_COUNT_FILE="/root/backup_count.txt"
RUNNING_CONTAINERS_FILE="/tmp/running_containers.txt"
LOG_FILE="/var/log/docker_backup.log"

# Additional directories to backup can be added here
ADDITIONAL_BACKUP_DIRS=()

# Ensure the backup directory exists
mkdir -p "$BACKUP_DIR"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    if [ -f "$RUNNING_CONTAINERS_FILE" ]; then
        log_message "Cleaning up temporary file: $RUNNING_CONTAINERS_FILE"
        rm -f "$RUNNING_CONTAINERS_FILE"
    fi
}

# Trap to ensure cleanup happens on script exit or interruption
trap cleanup EXIT

# Save the list of running containers
log_message "Saving the list of running containers..."
docker ps -q > "$RUNNING_CONTAINERS_FILE"

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
DOCKER_BACKUP_NAME="docker_volumes_$BACKUP_TIMESTAMP.tar"
ROOT_BACKUP_NAME="root_home_$BACKUP_TIMESTAMP.tar"

create_backup() {
    local src_dir=$1
    local backup_name=$2
    tar -cf "$BACKUP_DIR/$backup_name" "$src_dir"
    log_message "Backup created: $backup_name"
}

create_backup "$DOCKER_VOLUMES_DIR" "$DOCKER_BACKUP_NAME"
create_backup "$ROOT_HOME_DIR" "$ROOT_BACKUP_NAME"

for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    BACKUP_NAME="${dir##*/}_$BACKUP_TIMESTAMP.tar"
    create_backup "$dir" "$BACKUP_NAME"
done

# Upload backups to Backblaze B2
log_message "Uploading backups to Backblaze B2..."
upload_backup() {
    local backup_name=$1
    for i in {1..3}; do
        log_message "Uploading $backup_name to Backblaze B2 (attempt $i)..."
        b2 file upload --no-progress "$B2_BUCKET" "$BACKUP_DIR/$backup_name" "$backup_name" && return 0
        log_message "Upload failed for $backup_name (attempt $i). Retrying..."
        sleep 5
    done
    log_message "Failed to upload $backup_name after 3 attempts. Exiting."
    exit 1
}

upload_backup "$DOCKER_BACKUP_NAME"
upload_backup "$ROOT_BACKUP_NAME"

for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    BACKUP_NAME="${dir##*/}_$BACKUP_TIMESTAMP.tar"
    upload_backup "$BACKUP_NAME"
done

# Manage backup retention
log_message "Managing backup retention..."
delete_old_backups() {
    local key=$1
    BACKUP_FILES=($(b2 ls "$B2_BUCKET" | grep "$key" | sort | head -n -"$MAX_BACKUPS"))
    for backup in "${BACKUP_FILES[@]}"; do
        log_message "Deleting old backup: $backup"
        b2 delete-file-version "$B2_BUCKET" "$backup"
    done
}

delete_old_backups "docker_volumes"
delete_old_backups "root_home"

for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    delete_old_backups "${dir##*/}"
done

# Remove local backup files
log_message "Deleting local backup files..."
rm -f "$BACKUP_DIR/"*.tar

# Restart previously running containers
log_message "Restarting previously running containers..."
while IFS= read -r container_id; do
    docker start "$container_id" && \
    log_message "Restarted container: $container_id" || \
    log_message "Failed to restart container: $container_id"
done < "$RUNNING_CONTAINERS_FILE"

log_message "Backup process completed successfully."
