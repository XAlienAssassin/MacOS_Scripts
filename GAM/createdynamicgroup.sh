# Script to hide multiple Google groups from the global address list
# This script uses GAM (Google Apps Manager)

# Set the path to GAM executable
GAM_PATH="/Users/medinao/bin/gam7/gam"

# Check if GAM exists
if [ ! -f "$GAM_PATH" ]; then
    echo "ERROR: GAM not found at $GAM_PATH"
    echo "Please check the path and try again."
    exit 1
fi

echo "Starting script to hide groups from global address list..."
echo "Using GAM at: $GAM_PATH"

# ... existing code ...

# Define an array of groups to process
groups=(
    "vpn_business_office@saintandrews.net"
)

# Loop through each group and update it
for group in "${groups[@]}"; do
    echo "Processing: $group"
    $GAM_PATH update group "$group" includeinglobaladdresslist false
    echo "-------------"
done