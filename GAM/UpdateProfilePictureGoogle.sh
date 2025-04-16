# Script to update user profile photos using Google Apps Manager (GAM)
# This script downloads data from a Google Sheet and updates user photos

# Set the path to GAM executable
GAM_PATH="/Users/medinao/bin/gam7/gam"

# Check if GAM exists
if [ ! -f "$GAM_PATH" ]; then
    echo "ERROR: GAM not found at $GAM_PATH"
    echo "Please check the path and try again."
    exit 1
fi

echo "Starting script to update user profile photos..."
echo "Using GAM at: $GAM_PATH"

# Download the CSV file from Google Sheets
# Properly format the Google Sheet URL for CSV export
# Google Sheet ID
SHEET_ID="1W_Xnm-8mqu3JlSewhX3e12GCcVVHnxOhfPGSSbIzfJE"
# Direct export URL for CSV
CSV_EXPORT_URL="https://docs.google.com/spreadsheets/d/$SHEET_ID/export?format=csv&gid=0"
CSV_FILE="/Library/Google Sheets CSV/user_photos.csv"

# Create directory if it doesn't exist
mkdir -p "/Library/Google Sheets CSV"

echo "Downloading data from Google Sheet..."
curl -L "$CSV_EXPORT_URL" -o "$CSV_FILE"

if [ ! -f "$CSV_FILE" ]; then
    echo "ERROR: Failed to download CSV file"
    exit 1
fi

# Default photo URL if column B is empty
DEFAULT_PHOTO="https://github.com/XAlienAssassin/MacOS_Scripts/blob/main/SA_Logo.png"

# Process the CSV file
echo "Processing user data from CSV..."
# Skip the header row with tail -n +2
while IFS=, read -r email photo || [ -n "$email" ]; do
    # Remove any quotes that might be in the CSV
    email="${email//\"/}"
    photo="${photo//\"/}"
    
    # If photo URL is empty, use the default
    if [ -z "$photo" ]; then
        photo="$DEFAULT_PHOTO"
    fi
    
    echo "Processing: $email"
    $GAM_PATH user "$email" update photo "$photo"
    echo "------------------------"
done < <(tail -n +2 "$CSV_FILE")

# Clean up
echo "Profile photo update process completed."

