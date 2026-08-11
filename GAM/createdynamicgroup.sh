#!/bin/bash
# Script to hide multiple Google groups from the global address list
# This script uses GAM (Google Apps Manager)

# Set the path to GAM executable
GAM_PATH="/Users/orion.medina/bin/gam7/gam"

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
    "Casper-Department-Class-of-2025"
    "Casper-Department-Class-of-2026"
    "Casper-Department-Class-of-2027"
    "Casper-Department-Class-of-2028"
    "Casper-Department-Class-of-2029"
    "Casper-Department-Class-of-2030"
    "Casper-Department-Class-of-2031"
    "Casper-Department-Class-of-2032"
    "Casper-Department-Class-of-2033"
    "Casper-Department-Class-of-2034"
    "Casper-Department-Class-of-2035"
    "Casper-Department-Class-of-2036"
    "Casper-Department-Class-of-2037"
    "Casper-Department-Class-of-2038"
    "Casper-Department-Class-of-2039"
    "Casper-Department-Class-of-2040"
    "Casper-Department-Class-of-2041"
    "Casper-Department-Class-of-2042"
    "Casper-Department-Class-of-2043"
    "Casper-Department-Class-of-2044"
    "Casper-Department-Class-of-2045"
    "Casper-Department-Class-of-2046"
    "Casper-Department-Class-of-2047"
    "Casper-Department-Class-of-2048"
    "Casper-Department-Class-of-2049"
    "Casper-Department-Class-of-2050"
)

# Max number of groups to update at the same time
MAX_PARALLEL=5

# Update a single group
update_group() {
    local group="$1"
    echo "Processing: $group"
    $GAM_PATH update group "$group" includeinglobaladdresslist false
    echo "-------------"
}

# Launch updates in parallel, capping concurrency at MAX_PARALLEL
pids=()
for group in "${groups[@]}"; do
    update_group "$group" &
    pids+=("$!")

    if [ "${#pids[@]}" -ge "$MAX_PARALLEL" ]; then
        wait "${pids[0]}"
        pids=("${pids[@]:1}")
    fi
done

# Wait for any remaining background jobs to finish
wait

echo "All groups processed."