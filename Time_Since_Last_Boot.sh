#!/bin/bash

# Get the boot time in seconds since epoch
boot_time=$(sysctl -n kern.boottime | awk -F'[ ,]' '{print $4}')

# Get the current time in seconds since epoch
current_time=$(date +%s)

# Calculate the time since last boot in seconds
time_since_boot=$((current_time - boot_time))

# Convert seconds to human-readable format
days=$((time_since_boot / 86400))
hours=$((time_since_boot / 3600 % 24))
minutes=$((time_since_boot / 60 % 60))
seconds=$((time_since_boot % 60))

# Print the time since last boot
echo "<result>Time since last boot: $days days, $hours hours, $minutes minutes, $seconds seconds</result>"

# If you want to output just the number of seconds since last boot, you can use:
# echo "$time_since_boot"


