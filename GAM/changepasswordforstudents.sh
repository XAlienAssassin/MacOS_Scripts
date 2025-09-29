# Script to change the password for multiple users
# This script uses GAM (Google Apps Manager)

# Set the path to GAM executable
GAM_PATH="/Users/medinao/bin/gam7/gam"

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

# Loop through each users and update it
for user in "${users[@]}"; do
    echo "Processing: $user"
    $GAM_PATH update user $user password "StudentTemp2024!" changepassword true
    echo "-------------"
done