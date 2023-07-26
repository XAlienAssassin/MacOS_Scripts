#!/bin/bash

# Get the full name of the currently logged-in user
dscl . -read /Users/$(whoami) RealName | tail -n 1 | awk '{print $1, $2}'
# Display the full name

