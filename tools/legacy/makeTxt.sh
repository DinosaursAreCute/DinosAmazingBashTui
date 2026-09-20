#!/bin/bash

# Arguments
SRC_DIR="${1:-.}"
TARGET_DIR="${2:-.}"
SUFFIX="${3:-}"

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Process all files in the source directory
for file in "$SRC_DIR"/*; do
  if [ -f "$file" ]; then
    # Extract just the filename without path
    filename=$(basename -- "$file")
    echo "Copying $filename into $TARGET_DIR"
    # Copy file to target directory with updated name
    cp -- "$file" "$TARGET_DIR/${filename}${SUFFIX}.txt"
  fi
done
