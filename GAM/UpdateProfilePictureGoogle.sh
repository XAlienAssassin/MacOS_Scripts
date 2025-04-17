# Script to update user profile photos using Google Apps Manager (GAM)
# This script downloads data from a Google Sheet and updates user photos
# Log file path
# Create a timestamped log file name
timestamp=$(date +"%Y%m%d_%H%M%S")
logFile="/Library/Google Sheets CSV/user_photo_${timestamp}.log"

# Set up logging to both file and terminal
# Create the log file
touch "$logFile"

# Set up logging to both file and terminal without using tee
# Save original stdout and stderr
exec 3>&1 4>&2

# Redirect stdout and stderr to the log file
exec 1>>"$logFile" 2>&1

# Define a function to echo to both log file and original stdout
log() {
    echo "$@" >&1
    echo "$@" >&3
}

# Use log function instead of echo for all subsequent output
alias echo="log"

echo "Log file created at: $logFile"
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
SHEET_ID="1Pp2GdEdpzEMaBeiMs5btF69Z64N29HjpqcBMU3udplA"
# Sheet GID (specific sheet within the spreadsheet)
SHEET_GID="1290103477"
# Direct export URL for CSV
CSV_EXPORT_URL="https://docs.google.com/spreadsheets/d/$SHEET_ID/export?format=csv&gid=$SHEET_GID"
CSV_DIR="/Library/Google Sheets CSV"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CSV_FILE="$CSV_DIR/user_photos_$TIMESTAMP.csv"

# Create directory if it doesn't exist
mkdir -p "$CSV_DIR"

echo "Downloading data from Google Sheet..."
curl -L "$CSV_EXPORT_URL" -o "$CSV_FILE"

if [ ! -f "$CSV_FILE" ]; then
    echo "ERROR: Failed to download CSV file"
    exit 1
fi

# Default photo URL if column B is empty
DEFAULT_PHOTO="https://github.com/XAlienAssassin/MacOS_Scripts/blob/main/SA_Logo.png?raw=true"

# Process the CSV file
echo "Processing user data from CSV..."
# Debug: Display CSV content
echo "CSV file content:"
head -n 5 "$CSV_FILE"
echo "\n------------------------"

# Process the CSV file, using column A for email and column B for photo URL
cat "$CSV_FILE" | while IFS=, read -r email photo rest_of_line || [ -n "$email" ]; do
    # Remove any quotes that might be in the CSV
    email="${email//\"/}"
    photo="${photo//\"/}"
    
    # Skip empty lines or lines with empty email
    if [ -z "$email" ] || [ "$email" = "Email" ]; then
        continue
    fi
    
    # If photo URL is empty, use the default
    if [ -z "$photo" ]; then
        photo="$DEFAULT_PHOTO"
    fi
    
    # Ensure the photo URL has http:// prefix if it doesn't already
    if [[ ! "$photo" =~ ^https?:// ]]; then
        photo="http://$photo"
    fi
    
    echo "Processing: $email with photo: $photo"
    $GAM_PATH user "$email" update photo "$photo"
    echo "------------------------"
done

# Clean up
echo "Profile photo update process completed."