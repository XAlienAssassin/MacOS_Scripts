#!/bin/bash
# Script to update the Google profile photo for every user in an OU
# This script uses GAM (Google Apps Manager)

# Set the path to GAM executable
GAM_PATH="/Users/orion.medina/bin/gam7/gam"

# OU whose members will have their profile photo updated
# Verify/update via: $GAM_PATH print orgunits
OU_PATH=""

# Photo every user in the OU will be set to
PHOTO_URL="https://raw.githubusercontent.com/XAlienAssassin/MacOS_Scripts/refs/heads/main/SA_Logo.png"

# Check if GAM exists
if [ ! -f "$GAM_PATH" ]; then
    echo "ERROR: GAM not found at $GAM_PATH"
    echo "Please check the path and try again."
    exit 1
fi

echo "Starting script to update profile photos for users in OU: $OU_PATH"
echo "Using GAM at: $GAM_PATH"

# Pull the current member list of the OU so we can confirm before making changes
tmpfile=$(mktemp)
"$GAM_PATH" print users limittoou "$OU_PATH" fields primaryEmail 2>/dev/null | tail -n +2 > "$tmpfile"

emails=()
while IFS=, read -r email _; do
    emails+=("$email")
done < "$tmpfile"
rm -f "$tmpfile"

total="${#emails[@]}"

if [ "$total" -eq 0 ]; then
    echo "No users found in OU: $OU_PATH"
    exit 1
fi

echo ""
echo "Sample of users found ($total total in $OU_PATH):"
for email in "${emails[@]:0:5}"; do
    echo "  - $email"
done
echo ""
echo "Photo to apply: $PHOTO_URL"
echo ""

read -p "Update the profile photo for all $total users above? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted. No photos were changed."
    exit 0
fi

# GAM natively expands ou into every user directly in that OU
# (use ou_and_children instead of ou to also include nested sub-OUs)
"$GAM_PATH" ou "$OU_PATH" update photo "$PHOTO_URL"

echo "All users in $OU_PATH processed."
