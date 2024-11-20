#!/bin/bash

# Configuration
BACKUP_COUNT_FILE="/root/backup_count.txt"
LAST_COUNT_FILE="/root/last_backup_count.txt"
MAIL_FILE="/root/backup_email.txt"
TO_EMAIL="user@example.com"
SUBJECT="Backup Completed Notification"
LOG_FILE="/var/log/backup_notifications.log"

# Function for logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check if required files exist
if [ ! -f "$BACKUP_COUNT_FILE" ]; then
    log_message "ERROR: Backup count file does not exist: $BACKUP_COUNT_FILE"
    exit 1
fi

# Create last count file if it doesn't exist
if [ ! -f "$LAST_COUNT_FILE" ]; then
    cp "$BACKUP_COUNT_FILE" "$LAST_COUNT_FILE"
    log_message "Created initial last count file"
fi

# Check file permissions
if [ ! -w "$(dirname "$MAIL_FILE")" ]; then
    log_message "ERROR: Cannot write to mail file directory"
    exit 1
fi

# Check for differences between the current backup count and the last known count
if ! diff "$BACKUP_COUNT_FILE" "$LAST_COUNT_FILE" > /dev/null 2>&1; then
    # Differences found, backups have been created
    log_message "Backup completion detected"
    
    {
        echo "Backup completion detected on $(hostname) at $(date)"
        echo ""
        echo "The following cPanel accounts have new backups (latest backup counts):"
        diff "$LAST_COUNT_FILE" "$BACKUP_COUNT_FILE" | grep '>' | 
            awk '{print $2 " - new backup count: " $3}'
    } > "$MAIL_FILE"
    
    # Send email using mailx
    if mailx -s "$SUBJECT" "$TO_EMAIL" < "$MAIL_FILE" 2>/dev/null; then
        log_message "Email notification sent successfully"
    else
        log_message "ERROR: Failed to send email notification"
    fi

    # Update the last backup count file with the new state
    if cp "$BACKUP_COUNT_FILE" "$LAST_COUNT_FILE"; then
        log_message "Updated last backup count file"
    else
        log_message "ERROR: Failed to update last backup count file"
    fi
else
    log_message "No new backups detected"
fi

# Cleanup
rm -f "$MAIL_FILE"
