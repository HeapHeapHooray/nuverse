# Nerd.nu Minecraft Server Map Downloader & Manager

A lightweight, robust, and highly interactive Bash script to dynamically download, verify, unpack, and manage historical map archives from the legendary **nerd.nu** (r/mcpublic) Minecraft server network hosted at [mcp-dl.com](https://mcp-dl.com/).

---

## 📖 Background

**Nerd.nu** is one of the oldest active multiplayer Minecraft server networks, dating back to 2009. Over the years, the network has run multiple game servers (including Creative, PvE, and Chaos) across dozens of "revisions" (server resets). 

When a revision ends, the map is archived so players can explore their builds in single-player or host them locally. This manager allows you to browse and retrieve any of the 120+ historical maps, ensuring file integrity and organizing them cleanly for local play or server hosting.

---

## ✨ Features

- **Interactive Search Menu**: Dynamically fetches the list of all available archives, formats them in a clean two-column grid with file sizes, and lets you filter maps instantly by entering text.
- **Direct CLI Support**: Allows you to specify one or multiple maps directly on the command line, bypassing the interactive menu. Includes smart prefix and fuzzy-matching.
- **MD5 Checksum Verification**: Automatically fetches corresponding `.md5` hashes and validates file integrity using `md5sum` before extracting to prevent corrupted downloads.
- **Resilient Multi-Stage Processing**: Uses a `.tmp` workspace to download files safely. If a download is interrupted, it cleans up without polluting your output directories.
- **Auto-Folder Prefixing**: Automatically renames inner extracted folders to match the parent archive name (e.g. `minigames` extracts and renames to `ctf-2015-06-minigames_minigames`), ensuring name collisions do not occur.
- **Server-Ready Symlinks**: Automatically creates portable, relative symbolic links to the world folders under `./worlds/` so they can be easily loaded by your local server.

---

## 🛠 Requirements

The script relies on standard command-line tools commonly found on modern Linux distributions:
- `curl` (for fetching index pages and files)
- `tar` (for extracting `.tar.gz` archives)
- `realpath` (for creating portable relative symbolic links)
- `md5sum` (optional, for validating file checksums)

---

## 🚀 Getting Started

### Run Instantly (No Cloning Required)
You can run the script instantly without cloning the repository by running:
```bash
bash <(curl -fsSL https://nyan.nu/nuverse.sh)
```

### Manual Setup

#### 1. Make the Script Executable
Before running the script for the first time, ensure it has execution permissions:
```bash
chmod +x download_archives.sh
```

### 2. Run Interactively (Search & Select)
Run the script without arguments to open the terminal-based interactive selector:
```bash
./download_archives.sh
```
* **Filter the list**: Just type a keyword (e.g. `creative`, `pve`, `chaos`) and press `Enter` to search.
* **Clear active filter**: Type `c` and press `Enter`.
* **Select maps**: Enter space-separated numbers corresponding to the map indices you want to download (e.g., `1 12 45`), then press `Enter`.
* **Quit**: Type `q` or `exit`.

---

## 💻 Command-Line Reference

You can customize the script's behavior using standard command-line arguments.

```text
Usage: ./download_archives.sh [options] [archive_name1 archive_name2 ...]

Options:
  -h, --help           Show this help message and exit
  -l, --list           List all available archives on mcp-dl.com and exit
  -d, --dir <path>     Specify output directory (default: ./downloaded_archives)
  -w, --worlds-dir <p> Specify worlds symlink directory (default: ./worlds)
  -k, --keep           Keep downloaded .tar.gz and .md5 files after extraction
  -y, --yes            Auto-confirm overwriting existing folders
  --dry-run            Show download/unpack actions without executing them
```

### Examples

#### List All Archives with Sizes
To browse the entire directory without opening the interactive loop:
```bash
./download_archives.sh --list
```

#### Download a Specific Revision Directly
You can specify exact archive names or use fuzzy search keywords:
```bash
./download_archives.sh lobby-2016-12-heysofia.tar.gz ctf-2015-06-minigames
```

#### Keep Archives After Extraction
If you want to keep the original `.tar.gz` backups in your output directory:
```bash
./download_archives.sh -k ctf-2015-06-minigames
```

#### Custom Output Directories
To extract maps to a custom path and link the server worlds to a custom directory:
```bash
./download_archives.sh --dir ./my_backups --worlds-dir ./active_server_worlds ctf-2015-06-minigames
```

---

## 📂 Project Directory Structure

```text
.
├── download_archives.sh    # The manager script
├── downloaded_archives/    # Extracted archives (holds all folders/files)
│   └── ctf-2015-06-minigames/
│       └── ctf-2015-06-minigames_minigames/  # Renamed world folder
├── worlds/                 # Server-ready folder containing relative symlinks
│   └── ctf-2015-06-minigames_minigames -> ../downloaded_archives/ctf-2015-06-minigames/ctf-2015-06-minigames_minigames
└── README.md               # This documentation file
```

---

## 🔗 Links

- **Main Network Website**: [nerd.nu](https://nerd.nu/)
- **Official Subreddit**: [r/mcpublic](https://www.reddit.com/r/mcpublic/)
- **Map Archive Registry**: [mcp-dl.com](https://mcp-dl.com/)
