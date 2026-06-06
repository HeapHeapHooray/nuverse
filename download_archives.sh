#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
# We do not set -e here because we want custom error handling for downloads and MD5 verification.
set -o pipefail

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}========================================================================${NC}"
    echo -e "  ${BOLD}MCP-DL World Archive Downloader & Unpacker${NC}"
    echo -e "${CYAN}========================================================================${NC}"
}

show_help() {
    print_header
    echo -e "Usage: $0 [options] [archive_name1 archive_name2 ...]\n"
    echo -e "Options:"
    echo -e "  -h, --help           Show this help message and exit"
    echo -e "  -l, --list           List all available archives on mcp-dl.com and exit"
    echo -e "  -d, --dir <path>     Specify output directory (default: ./downloaded_archives)"
    echo -e "  -w, --worlds-dir <p> Specify worlds symlink directory (default: ./worlds)"
    echo -e "  -k, --keep           Keep downloaded .tar.gz and .md5 files after extraction"
    echo -e "  -y, --yes            Auto-confirm overwriting existing folders"
    echo -e "  --dry-run            Show download/unpack actions without executing them"
    echo -e "\nExamples:"
    echo -e "  $0                  # Run interactively with filterable menu"
    echo -e "  $0 lobby-2016-12-heysofia.tar.gz     # Download specific archive"
    echo -e "  $0 -k ctf-2015-06-minigames.tar.gz   # Download and keep the tarball"
    echo -e "  $0 --dir ./my_maps ctf-2016-06-world.tar.gz"
}

# Check dependencies
dependencies=("curl" "tar" "realpath")
missing_deps=()
for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        missing_deps+=("$dep")
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "${RED}[!] Error: Missing required dependencies: ${missing_deps[*]}${NC}"
    echo -e "${YELLOW}[*] Please install them and try again.${NC}"
    exit 1
fi

# Detect download tool
if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_CMD="curl -L -# -o"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD_CMD="wget -q --show-progress -O"
fi

# MD5 utility check
HAS_MD5SUM=false
if command -v md5sum >/dev/null 2>&1; then
    HAS_MD5SUM=true
fi

# Default options
DOWNLOAD_DIR="./downloaded_archives"
WORLDS_DIR="./worlds"
KEEP_ARCHIVES=false
YES_TO_ALL=false
DRY_RUN=false
LIST_ONLY=false
SPECIFIED_ARCHIVES=()

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        -d|--dir)
            if [ -z "$2" ]; then
                echo -e "${RED}[!] Error: --dir requires an argument.${NC}"
                exit 1
            fi
            DOWNLOAD_DIR="$2"
            shift 2
            ;;
        -w|--worlds-dir)
            if [ -z "$2" ]; then
                echo -e "${RED}[!] Error: --worlds-dir requires an argument.${NC}"
                exit 1
            fi
            WORLDS_DIR="$2"
            shift 2
            ;;
        -k|--keep)
            KEEP_ARCHIVES=true
            shift
            ;;
        -y|--yes)
            YES_TO_ALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo -e "${RED}[!] Error: Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
        *)
            SPECIFIED_ARCHIVES+=("$1")
            shift
            ;;
    esac
done

# Fetch available archives from mcp-dl.com
echo -e "${BLUE}[*] Fetching archive list from https://mcp-dl.com/...${NC}"
INDEX_HTML=$(mktemp)
if ! curl -s "https://mcp-dl.com/" > "$INDEX_HTML"; then
    echo -e "${RED}[!] Error: Failed to fetch index page from https://mcp-dl.com/${NC}"
    rm -f "$INDEX_HTML"
    exit 1
fi

mapfile -t RAW_LIST < <(grep -oE 'href="[^"]+\.tar\.gz"[^>]*>[^<]+</a></td><td class="size">[^<]+</td>' "$INDEX_HTML" | sed -E 's/href="([^"]+)".*class="size">([^<]+)<\/td>/\1|\2/' | sort -f)
rm -f "$INDEX_HTML"

if [ ${#RAW_LIST[@]} -eq 0 ]; then
    echo -e "${RED}[!] Error: Could not find any .tar.gz archives in the page content.${NC}"
    exit 1
fi

ARCHIVE_NAMES=()
ARCHIVE_SIZES=()

for row in "${RAW_LIST[@]}"; do
    IFS='|' read -r name size <<< "$row"
    ARCHIVE_NAMES+=("$name")
    ARCHIVE_SIZES+=("$size")
done

print_columns() {
    local filter="$1"
    local matching_indices=()
    
    for i in "${!ARCHIVE_NAMES[@]}"; do
        if [ -z "$filter" ] || [[ "${ARCHIVE_NAMES[$i]}" =~ "$filter" ]]; then
            matching_indices+=($i)
        fi
    done
    
    local num_matches=${#matching_indices[@]}
    if [ $num_matches -eq 0 ]; then
        echo -e "  ${RED}No archives matched your search \"$filter\".${NC}"
        return
    fi
    
    # Display in 2 columns
    local COLS=2
    local ROWS=$(( (num_matches + COLS - 1) / COLS ))
    for ((r=0; r<ROWS; r++)); do
        local line=""
        for ((c=0; c<COLS; c++)); do
            local idx=$(( r + c * ROWS ))
            if [ $idx -lt $num_matches ]; then
                local real_idx=${matching_indices[$idx]}
                local name="${ARCHIVE_NAMES[$real_idx]}"
                local size="${ARCHIVE_SIZES[$real_idx]}"
                
                local index_str=$(printf "%3d" $((real_idx + 1)))
                local name_display="${name}"
                if [ ${#name_display} -gt 35 ]; then
                    name_display="${name_display:0:32}..."
                fi
                local pad_len=$(( 35 - ${#name_display} ))
                if [ $pad_len -lt 0 ]; then pad_len=0; fi
                local padding=$(printf '%*s' $pad_len "")
                
                local item="[${GREEN}${index_str}${NC}] ${BOLD}${name_display}${NC}${padding} (${CYAN}${size}${NC})"
                line="${line}${item}  |  "
            fi
        done
        # Strip trailing separator
        line="${line%  |  }"
        echo -e "  $line"
    done
}

# If user wanted only list, print and exit
if [ "$LIST_ONLY" = true ]; then
    print_header
    echo -e "${YELLOW}Available Archives on mcp-dl.com:${NC}\n"
    print_columns ""
    exit 0
fi

SELECTED_INDICES=()

# Determine selected archives based on direct specification or interactive mode
if [ ${#SPECIFIED_ARCHIVES[@]} -gt 0 ]; then
    for spec in "${SPECIFIED_ARCHIVES[@]}"; do
        found_idx=-1
        # Try exact or exact+.tar.gz
        for i in "${!ARCHIVE_NAMES[@]}"; do
            if [ "${ARCHIVE_NAMES[$i]}" = "$spec" ] || [ "${ARCHIVE_NAMES[$i]}" = "${spec}.tar.gz" ]; then
                found_idx=$i
                break
            fi
        done
        
        # If not found, fuzzy match
        if [ $found_idx -eq -1 ]; then
            for i in "${!ARCHIVE_NAMES[@]}"; do
                if [[ "${ARCHIVE_NAMES[$i]}" =~ "$spec" ]]; then
                    found_idx=$i
                    break
                fi
            done
        fi
        
        if [ $found_idx -ne -1 ]; then
            SELECTED_INDICES+=($found_idx)
        else
            echo -e "${RED}[!] Error: Could not find any archive matching \"$spec\" on mcp-dl.com.${NC}"
            echo -e "${YELLOW}[*] Use '$0 --list' to see all ${#ARCHIVE_NAMES[@]} available archives.${NC}"
            exit 1
        fi
    done
else
    # Interactive mode
    FILTER=""
    while true; do
        clear
        print_header
        echo -e "${YELLOW}Available Archives:${NC}"
        if [ -n "$FILTER" ]; then
            echo -e "${BLUE}Filtering by: \"$FILTER\" (Type 'c' to clear filter)${NC}\n"
        else
            echo -e "${BLUE}Showing all archives (Type a search term like 'creative' or 'lobby' to filter)${NC}\n"
        fi
        
        print_columns "$FILTER"
        
        echo -e "\n${CYAN}========================================================================${NC}"
        echo -e "  ${BOLD}Options:${NC}"
        echo -e "    - Enter space-separated ${GREEN}numbers${NC} to select maps (e.g. ${GREEN}1 15 42${NC})"
        echo -e "    - Type any ${YELLOW}text${NC} to filter the list (e.g. ${YELLOW}creative${NC})"
        echo -e "    - Type ${YELLOW}c${NC} to clear the active filter"
        echo -e "    - Type ${RED}q${NC} to quit"
        echo -e "${CYAN}========================================================================${NC}"
        read -p "Choose option: " USER_INPUT
        
        if [ -z "$USER_INPUT" ]; then
            continue
        fi
        
        if [[ "$USER_INPUT" =~ ^[0-9[:space:]]+$ ]]; then
            valid=true
            for num in $USER_INPUT; do
                idx=$((num - 1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#ARCHIVE_NAMES[@]} ]; then
                    SELECTED_INDICES+=($idx)
                else
                    echo -e "${RED}[!] Invalid archive number: $num. Select between 1 and ${#ARCHIVE_NAMES[@]}.${NC}"
                    valid=false
                    SELECTED_INDICES=()
                    sleep 1.5
                    break
                fi
            done
            if [ "$valid" = true ]; then
                break
            fi
        elif [ "$USER_INPUT" = "q" ] || [ "$USER_INPUT" = "quit" ] || [ "$USER_INPUT" = "exit" ]; then
            echo -e "${BLUE}Goodbye!${NC}"
            exit 0
        elif [ "$USER_INPUT" = "c" ] || [ "$USER_INPUT" = "clear" ]; then
            FILTER=""
        else
            FILTER="$USER_INPUT"
        fi
    done
fi

# Print selection summary
echo -e "\n${GREEN}[+] Selected archives to download and unpack:${NC}"
for idx in "${SELECTED_INDICES[@]}"; do
    name="${ARCHIVE_NAMES[$idx]}"
    size="${ARCHIVE_SIZES[$idx]}"
    echo -e "  - ${BOLD}$name${NC} ($size)"
done

if [ "$DRY_RUN" = true ]; then
    echo -e "\n${YELLOW}[*] Dry run mode enabled. No files will be downloaded or extracted.${NC}"
    exit 0
fi

# Ensure output and tmp directories exist
TMP_DIR="${DOWNLOAD_DIR}/.tmp"
mkdir -p "$TMP_DIR"

echo -e "\n${BLUE}[*] Output directory: ${DOWNLOAD_DIR}${NC}"

for idx in "${SELECTED_INDICES[@]}"; do
    name="${ARCHIVE_NAMES[$idx]}"
    url="https://mcp-dl.com/${name}"
    md5_url="${url}.md5"
    
    extract_folder_name="${name%.tar.gz}"
    extract_path="${DOWNLOAD_DIR}/${extract_folder_name}"
    
    echo -e "\n${CYAN}========================================================================${NC}"
    echo -e "  Processing: ${BOLD}${name}${NC}"
    echo -e "${CYAN}========================================================================${NC}"
    
    # Check if directory already exists
    if [ -d "$extract_path" ] && [ "$(ls -A "$extract_path" 2>/dev/null)" ] && [ "$YES_TO_ALL" != true ]; then
        echo -e "${YELLOW}[!] Warning: Folder \"${extract_path}\" already exists and is not empty.${NC}"
        read -p "Overwrite and delete its current contents? (y/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}[*] Skipping ${name}...${NC}"
            continue
        fi
    fi
    
    # 1. Download MD5 file if checksum check is possible
    MD5_DOWNLOADED=false
    if [ "$HAS_MD5SUM" = true ]; then
        echo -e "${BLUE}[*] Fetching MD5 checksum...${NC}"
        if curl -s -f "$md5_url" -o "${TMP_DIR}/${name}.md5"; then
            MD5_DOWNLOADED=true
        else
            echo -e "${YELLOW}[!] Warning: No MD5 checksum found for ${name}. Skipping checksum verification.${NC}"
        fi
    fi
    
    # 2. Download the archive
    echo -e "${BLUE}[*] Downloading archive (${ARCHIVE_SIZES[$idx]})...${NC}"
    if [ "$DOWNLOAD_CMD" = "curl -L -# -o" ]; then
        # Run curl
        curl -L -# -o "${TMP_DIR}/${name}" "$url"
    else
        # Run wget
        wget -q --show-progress -O "${TMP_DIR}/${name}" "$url"
    fi
    
    if [ $? -ne 0 ] || [ ! -f "${TMP_DIR}/${name}" ]; then
        echo -e "${RED}[!] Error: Failed to download ${name}.${NC}"
        rm -f "${TMP_DIR}/${name}.md5"
        continue
    fi
    
    # 3. Verify MD5 sum
    if [ "$MD5_DOWNLOADED" = true ]; then
        echo -e "${BLUE}[*] Verifying checksum...${NC}"
        cd "$TMP_DIR"
        if md5sum -c "${name}.md5" >/dev/null 2>&1; then
            echo -e "${GREEN}[+] Checksum matches! File integrity verified.${NC}"
            cd - >/dev/null
        else
            echo -e "${RED}[!] Critical: MD5 validation failed for ${name}! The file may be corrupted.${NC}"
            read -p "Do you still want to extract it? (y/N): " FORCE_EXTRACT
            cd - >/dev/null
            if [[ ! "$FORCE_EXTRACT" =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}[*] Skipping extraction for ${name}...${NC}"
                rm -f "${TMP_DIR}/${name}" "${TMP_DIR}/${name}.md5"
                continue
            fi
        fi
    fi
    
    # 4. Unpack archive
    echo -e "${BLUE}[*] Extracting to \"${extract_path}\"...${NC}"
    # Prepare clean extraction folder
    mkdir -p "$extract_path"
    rm -rf "${extract_path:?}"/*
    
    # Extract
    if tar -xzf "${TMP_DIR}/${name}" -C "$extract_path"; then
        echo -e "${GREEN}[+] Successfully unpacked ${name} into ${extract_path}!${NC}"
        # Find all directories containing level.dat, sorted by depth descending
        declare -A seen_dirs
        world_dirs=()
        while IFS= read -r level_dat; do
            [ -z "$level_dat" ] && continue
            dir_name=$(dirname "$level_dat")
            dir_abspath=$(realpath "$dir_name")
            if [ -z "${seen_dirs[$dir_abspath]}" ]; then
                seen_dirs[$dir_abspath]=1
                world_dirs+=("$dir_name")
            fi
        done < <(find "$extract_path" -type f -iname "level.dat" | awk -F'/' '{print NF "\t" $0}' | sort -nr | cut -f2-)

        if [ ${#world_dirs[@]} -eq 0 ]; then
            echo -e "${YELLOW}[!] Warning: No level.dat found in the extracted files. Checking for any subdirectories...${NC}"
            # Fallback to the old behavior: treat direct subdirectories as worlds
            has_subdirs=false
            for sub in "$extract_path"/*; do
                if [ -d "$sub" ]; then
                    has_subdirs=true
                    sub_basename=$(basename "$sub")
                    if [[ "$sub_basename" != "${extract_folder_name}"* ]]; then
                        mv "$sub" "${extract_path}/${extract_folder_name}_${sub_basename}"
                        sub_basename="${extract_folder_name}_${sub_basename}"
                    fi
                    mkdir -p "$WORLDS_DIR"
                    echo -e "${BLUE}[*] Symlinking folder \"${sub_basename}\" into ${WORLDS_DIR}...${NC}"
                    rm -rf "${WORLDS_DIR}/${sub_basename}"
                    ln -sf "$(realpath --relative-to="$WORLDS_DIR" "${extract_path}/${sub_basename}")" "${WORLDS_DIR}/${sub_basename}"
                fi
            done
            if [ "$has_subdirs" = false ]; then
                # If there are no subdirectories either, symlink the extract_path itself
                mkdir -p "$WORLDS_DIR"
                echo -e "${BLUE}[*] Symlinking extract path \"${extract_folder_name}\" into ${WORLDS_DIR}...${NC}"
                rm -rf "${WORLDS_DIR}/${extract_folder_name}"
                ln -sf "$(realpath --relative-to="$WORLDS_DIR" "$extract_path")" "${WORLDS_DIR}/${extract_folder_name}"
            fi
        else
            # Process the identified world directories
            for world_dir in "${world_dirs[@]}"; do
                world_dir_abspath=$(realpath "$world_dir")
                extract_path_abspath=$(realpath "$extract_path")
                
                if [ "$world_dir_abspath" = "$extract_path_abspath" ]; then
                    sub_basename="$extract_folder_name"
                    target_world_path="$extract_path"
                else
                    sub_basename=$(basename "$world_dir")
                    if [ "$sub_basename" = "$extract_folder_name" ]; then
                        target_name="$extract_folder_name"
                    elif [[ "$sub_basename" == "${extract_folder_name}"_* ]]; then
                        target_name="$sub_basename"
                    else
                        target_name="${extract_folder_name}_${sub_basename}"
                    fi
                    
                    target_world_path="${extract_path}/${target_name}"
                    
                    if [ "$world_dir_abspath" != "$(realpath "$target_world_path" 2>/dev/null)" ]; then
                        echo -e "${BLUE}[*] Renaming and moving world folder \"${sub_basename}\" to \"${target_name}\"...${NC}"
                        rm -rf "$target_world_path"
                        mv "$world_dir" "$target_world_path"
                    fi
                    sub_basename="$target_name"
                fi
                
                mkdir -p "$WORLDS_DIR"
                echo -e "${BLUE}[*] Symlinking world folder \"${sub_basename}\" into ${WORLDS_DIR}...${NC}"
                rm -rf "${WORLDS_DIR}/${sub_basename}"
                ln -sf "$(realpath --relative-to="$WORLDS_DIR" "$target_world_path")" "${WORLDS_DIR}/${sub_basename}"
            done
        fi
    else
        echo -e "${RED}[!] Error: Failed to unpack ${name}.${NC}"
    fi
    
    # 5. Cleanup / Save Archive
    if [ "$KEEP_ARCHIVES" = true ]; then
        echo -e "${BLUE}[*] Moving archive to output directory...${NC}"
        mv -f "${TMP_DIR}/${name}" "${DOWNLOAD_DIR}/${name}"
        if [ "$MD5_DOWNLOADED" = true ]; then
            mv -f "${TMP_DIR}/${name}.md5" "${DOWNLOAD_DIR}/${name}.md5"
        fi
    else
        echo -e "${BLUE}[*] Cleaning up temporary download files...${NC}"
        rm -f "${TMP_DIR}/${name}" "${TMP_DIR}/${name}.md5"
    fi
done

# Remove tmp dir if empty
rmdir "$TMP_DIR" 2>/dev/null || true

echo -e "\n${GREEN}========================================================================${NC}"
echo -e "  ${BOLD}All processing finished!${NC}"
echo -e "${GREEN}========================================================================${NC}\n"
