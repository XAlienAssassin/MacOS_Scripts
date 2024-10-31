# Get the current time on the macOS computer
current_time=$(date +"%s")

# Get the time from the Apple time server
apple_time=$(dscacheutil -q time | awk '/time/ {print $2}')

echo $apple_time