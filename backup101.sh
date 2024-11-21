#!/bin/bash

# Variables
DOCKER_VOLUMES_DIR="/var/lib/docker/volumes"
ROOT_HOME_DIR="/root"
BACKUP_DIR="/mnt/backups"
B2_BUCKET="backup101"
MAX_BACKUPS=7  # Number of backups to keep
BACKUP_COUNT_FILE="/root/backup_count.txt"
RUNNING_CONTAINERS_FILE="/tmp/running_containers.txt"
LOG_FILE="/var/log/docker_backup.log"
TMP_DIR="/tmp"

# Additional directories to backup can be added here
ADDITIONAL_BACKUP_DIRS=()

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
DOCKER_BACKUP_NAME="docker_volumes_$BACKUP_TIMESTAMP.tar"
ROOT_BACKUP_NAME="root_home_$BACKUP_TIMESTAMP.tar"

# Function to create a backup
create_backup() {
    local src_dir=$1
    local backup_name=$2
    tar -cf "$BACKUP_DIR/$backup_name" "$src_dir"
    if [ $? -ne 0 ]; then
        log_message "Failed to create backup for $src_dir."
        exit 1
    fi
}

# Create backups for specified directories
create_backup "$DOCKER_VOLUMES_DIR" "$DOCKER_BACKUP_NAME"
create_backup "$ROOT_HOME_DIR" "$ROOT_BACKUP_NAME"

# Create backups for additional directories
for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    BACKUP_NAME="${dir##*/}_$BACKUP_TIMESTAMP.tar"
    create_backup "$dir" "$BACKUP_NAME"
done

# Upload backups to Backblaze B2
log_message "Uploading backups to Backblaze B2..."
upload_backup() {
    local backup_name=$1
    b2 file upload --no-progress "$B2_BUCKET" "$BACKUP_DIR/$backup_name" "$backup_name"
    if [ $? -ne 0 ]; then
        log_message "Failed to upload backup $backup_name to Backblaze B2."
        exit 1
    fi
}

upload_backup "$DOCKER_BACKUP_NAME"
upload_backup "$ROOT_BACKUP_NAME"

# Upload backups for additional directories
for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    BACKUP_NAME="${dir##*/}_$BACKUP_TIMESTAMP.tar"
    upload_backup "$BACKUP_NAME"
done

# Update and manage backup retention
log_message "Managing backup retention..."
BACKUP_COUNT["docker_volumes"]=$(( ${BACKUP_COUNT["docker_volumes"]:-0} + 1 ))
BACKUP_COUNT["root_home"]=$(( ${BACKUP_COUNT["root_home"]:-0} + 1 ))

# Manage backup retention for additional directories
for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    BACKUP_COUNT["${dir##*/}"]=$(( ${BACKUP_COUNT["${dir##*/}"]:-0} + 1 ))
done

# Function to delete old backups
delete_old_backups() {
    local key=$1
    if [ "${BACKUP_COUNT["$key"]}" -gt "$MAX_BACKUPS" ]; then
        OLDEST_BACKUP_NUMBER=$(( BACKUP_COUNT["$key"] - MAX_BACKUPS ))
        OLDEST_BACKUP_NAME="${key}_$(date -d "-$OLDEST_BACKUP_NUMBER days" '+%Y%m%d%H%M%S').tar"

        log_message "Deleting old backup: $OLDEST_BACKUP_NAME"
        b2 delete-file-version "$B2_BUCKET" "$OLDEST_BACKUP_NAME"
        if [ $? -eq 0 ]; then
            log_message "Successfully deleted old backup: $OLDEST_BACKUP_NAME"
        else
            log_message "Failed to delete old backup: $OLDEST_BACKUP_NAME"
        fi
    fi
}

delete_old_backups "docker_volumes"
delete_old_backups "root_home"

# Delete old backups for additional directories
for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    delete_old_backups "${dir##*/}"
done

# Remove local backup files
log_message "Deleting local backup files..."
rm -f "$BACKUP_DIR/$DOCKER_BACKUP_NAME" "$BACKUP_DIR/$ROOT_BACKUP_NAME"

# Remove local backup files for additional directories
for dir in "${ADDITIONAL_BACKUP_DIRS[@]}"; do
    BACKUP_NAME="${dir##*/}_$BACKUP_TIMESTAMP.tar"
    rm -f "$BACKUP_DIR/$BACKUP_NAME"
done

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

