## Docker Volume Backup Script

This script automates the process of backing up Docker container volumes and the /root home directory to Backblaze B2, stopping all running containers during the backup process, and restarting them afterward. It ensures that old backups are deleted from the Backblaze B2 bucket, maintaining a specified number of backup files for efficient storage management.


---

Features:

Container Backup: Backs up Docker container volumes and the /root home directory to a specified directory.

Stop Running Containers: Stops all running Docker containers to ensure consistent backups.

Upload to Backblaze B2: Uploads backup files (tar/zip) to your Backblaze B2 bucket.

Backup Retention: Keeps a defined number of backups and deletes older ones from Backblaze B2 automatically.

Restart Containers: Restores the previously running containers after backup is complete.



---

Usage:

1. Set Up Your Environment:

Ensure that Docker and Backblaze B2 CLI tools (b2) are installed and configured.

Create a backups directory or change the backup directory in the script to an alternate location.



2. Configure Variables:
Edit the script to set the following environment variables:

BACKUP_DIR: The directory to store local backups before uploading.

B2_BUCKET: The Backblaze B2 bucket name where backups will be stored.

MAX_BACKUPS: The number of backups to retain in the Backblaze B2 bucket.



3. Run the Script:
Run the script on your server to initiate the backup process:

./backup101.sh


4. Log Files:
The script logs all activity into /var/log/docker_backup.log, including errors, warnings, and success messages.




---

How It Works:

Backup Process: The script archives Docker container volumes and the /root home directory, compresses them, and uploads the archives to Backblaze B2.

Stopping Containers: All Docker containers are stopped during the backup to ensure consistency. The container IDs are saved and then restarted after the backup process is finished.

Backup Retention: The script checks the existing backups on Backblaze B2 and deletes any backups that are older than the specified retention limit (MAX_BACKUPS).



---

Example Output:

2024-11-20 13:01:20 - Saving the list of running containers...
2024-11-20 13:01:20 - Stopping all running Docker containers...
2024-11-20 13:01:21 - Creating backup archives...
2024-11-20 13:01:30 - Uploading backups to Backblaze B2...
2024-11-20 13:02:00 - Deleting old backups...
2024-11-20 13:03:00 - Restarting the containers that were running...
2024-11-20 13:03:15 - Backup process completed successfully.


---

Installation & Setup:

1. Install Docker:
If Docker isn't installed, follow the official installation instructions for your system:
https://docs.docker.com/get-docker/


2. Install Backblaze B2 CLI:
Follow the Backblaze B2 CLI installation guide here:
https://www.backblaze.com/b2/docs/


3. Set Up Backblaze B2:
Create a Backblaze B2 account and configure the CLI by running:

b2 authorize_account <account_id> <application_key>


4. Configure the Script:
Edit the script to set the BACKUP_DIR, B2_BUCKET, and MAX_BACKUPS values to match your setup.




---

License:

This script is released under the MIT License. You are free to use, modify, and distribute it, provided you include the original license in any derivative works.


---

Contributing:

Feel free to fork the repository, make improvements, and submit pull requests. If you encounter any issues or have feature requests, please open an issue on GitHub.


