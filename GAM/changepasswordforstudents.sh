#!/bin/bash
# Script to change the password for multiple users
# This script uses GAM (Google Apps Manager)

# Set the path to GAM executable
GAM_PATH="/Users/orion.medina/bin/gam7/gam"

# Check if GAM exists
if [ ! -f "$GAM_PATH" ]; then
    echo "ERROR: GAM not found at $GAM_PATH"
    echo "Please check the path and try again."
    exit 1
fi

echo "Starting script to change password for multiple users..."
echo "Using GAM at: $GAM_PATH"

# ... existing code ...

# Define an array of users to process
users=(
    ""
)

# Max number of users to update at the same time
MAX_PARALLEL=5

# Update a single user
update_user() {
    local user="$1"
    echo "Processing: $user"
    $GAM_PATH update user "$user" password "StudentTemp2024!" changepassword true
    echo "-------------"
}

# Launch updates in parallel, capping concurrency at MAX_PARALLEL
pids=()
for user in "${users[@]}"; do
    update_user "$user" &
    pids+=("$!")

    if [ "${#pids[@]}" -ge "$MAX_PARALLEL" ]; then
        wait "${pids[0]}"
        pids=("${pids[@]:1}")
    fi
done

# Wait for any remaining background jobs to finish
wait

echo "All users processed."