#!/usr/bin/env bash

# Script: extract.sh
# Usage: extract.sh [-f] file1 [file2 ...]
#   -f: extract each archive into a folder named after the archive (without extension)
#   For .tar.* archives, performs intelligent extraction:
#       - If 7z extracts directly to final contents (e.g., .tar.gz), just use that
#       - If 7z extracts to a .tar file first (e.g., .tar.xz), do a second pass

set -euo pipefail

# ---------------- Helper Functions ----------------

# Get the base name of an archive file (without extension(s)).
# For .tar.* files, strips the whole .tar.* suffix.
# For other files, strips the last extension only.
get_basename() {
    local f="$1"
    # Check for .tar. followed by at least one alnum (e.g., .tar.gz, .tar.bz2, .tar.xz)
    if [[ "$f" =~ \.tar\.[a-zA-Z0-9]+$ ]]; then
        echo "${f%.tar.*}"
    else
        echo "${f%.*}"
    fi
}

# Check if a file is a .tar.* archive
is_tar_dot_star() {
    [[ "$1" =~ \.tar\.[a-zA-Z0-9]+$ ]]
}

# Run a command in a new foot terminal (closes automatically when done)
run_in_foot() {
    local cmd="$1"
    local title="${2:-Extracting...}"
    
    # Use foot without --hold - will close when command completes
    foot --title="$title" bash -c "$cmd"
}

# ---------------- Option Parsing ----------------

extract_to_folder=false
files=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f)
            extract_to_folder=true
            shift
            ;;
        --) # end of options
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            files+=("$1")
            shift
            ;;
    esac
done

# If no files were given, show usage and exit
if [[ ${#files[@]} -eq 0 ]]; then
    echo "Usage: $0 [-f] archive1 [archive2 ...]" >&2
    echo "  -f : extract each archive into a folder named after the archive" >&2
    exit 1
fi

# Check that 7z is available
if ! command -v 7z &> /dev/null; then
    echo "Error: 7z command not found. Please install p7zip or equivalent." >&2
    exit 1
fi

# Check that foot is available
if ! command -v foot &> /dev/null; then
    echo "Warning: foot not found, falling back to direct extraction" >&2
    USE_FOOT=false
else
    USE_FOOT=true
fi

# ---------------- Main Processing ----------------

for file in "${files[@]}"; do
    # Skip if not a regular file
    if [[ ! -f "$file" ]]; then
        echo "Warning: '$file' is not a regular file, skipping." >&2
        continue
    fi

    base="$(get_basename "$file")"
    # Determine output directory
    if [[ "$extract_to_folder" == true ]]; then
        out_dir="$base"
    else
        out_dir="."
    fi

    # Create output directory if needed (and not current)
    if [[ "$out_dir" != "." && ! -d "$out_dir" ]]; then
        mkdir -p "$out_dir"
    fi

    echo "Processing: $file -> $out_dir"

    # Get absolute path for the file
    abs_file="$(realpath "$file")"
    abs_out_dir="$(realpath "$out_dir" 2>/dev/null || echo "$out_dir")"

    if is_tar_dot_star "$file"; then
        # ---- Handle .tar.* archives ----
        # Create a temp directory
        temp_dir=$(mktemp -d)
        
        # Build the extraction command for step 1
        extract_cmd="echo '=== First pass: extracting $abs_file ===' && "
        extract_cmd+="7z x '$abs_file' -o'$temp_dir' -y && "
        extract_cmd+="echo '=== First pass complete ==='"
        
        # Run first extraction in foot terminal
        if [[ "$USE_FOOT" == true ]]; then
            run_in_foot "$extract_cmd" "Extracting: $(basename "$file") (Step 1/2)"
        else
            eval "$extract_cmd"
        fi
        
        # Check if first extraction succeeded
        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to extract $file" >&2
            rm -rf "$temp_dir"
            continue
        fi
        
        # Look for a .tar file in the temp directory
        tar_file=$(find "$temp_dir" -maxdepth 1 -name "*.tar" -type f | head -n1)
        
        if [[ -n "$tar_file" ]]; then
            # We have a .tar file - double extraction needed
            echo "  Detected .tar intermediate file, performing second extraction..."
            
            # Build the second extraction command
            second_cmd="echo '=== Second pass: extracting $(basename "$tar_file") ===' && "
            second_cmd+="7z x '$tar_file' -o'$abs_out_dir' -y && "
            second_cmd+="echo '=== Second pass complete ==='"
            
            # Run second extraction in foot terminal
            if [[ "$USE_FOOT" == true ]]; then
                run_in_foot "$second_cmd" "Extracting: $(basename "$file") (Step 2/2)"
            else
                eval "$second_cmd"
            fi
            
            # Clean up temp directory
            rm -rf "$temp_dir"
        else
            # No .tar file found - just move everything to out_dir
            echo "  No .tar intermediate found, moving extracted files..."
            if [[ "$out_dir" != "." ]]; then
                find "$temp_dir" -mindepth 1 -maxdepth 1 -exec mv -f {} "$out_dir/" \; 2>/dev/null || true
            else
                find "$temp_dir" -mindepth 1 -maxdepth 1 -exec mv -f {} ./ \; 2>/dev/null || true
            fi
            rm -rf "$temp_dir"
        fi

    else
        # ---- Single extraction for all other archives ----
        extract_cmd="echo '=== Extracting: $(basename "$file") ===' && "
        extract_cmd+="7z x '$abs_file' -o'$abs_out_dir' -y && "
        extract_cmd+="echo '=== Extraction complete ==='"
        
        if [[ "$USE_FOOT" == true ]]; then
            run_in_foot "$extract_cmd" "Extracting: $(basename "$file")"
        else
            eval "$extract_cmd"
        fi
    fi

    echo "Done: $file"
done

echo "All operations completed."
