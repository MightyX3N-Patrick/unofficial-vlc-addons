# Unofficial VLC Addons

This project enables **Stremio addon support** directly within VLC Media Player. It uses a suite of Lua scripts to host a local HTTP server, provide service discovery, and allow for content management.[cite: 3, 4, 5]

---

## 🛠 Project Components

*   **`unofficial_vlc_intf.lua`**: The core interface script that runs a local TCP HTTP server on port 8181.[cite: 4]
*   **`unofficial_vlc_addons.lua`**: Service Discovery script that adds the "Unofficial VLC Addons" node to the VLC playlist sidebar.[cite: 3]
*   **`unofficial_vlc_playlist.lua`**: A playlist parser for handling JSON data from the local server.[cite: 1]
*   **`unofficial_vlc_manager.lua`**: A VLC Extension (GUI) to add, remove, or toggle Stremio addons.[cite: 5]
*   **`install.bat`**: An automated Windows installer and configuration script.[cite: 2]

---

## 🚀 Installation

### Automatic (Windows)
1. Download the repository files.
2. Run **`install.bat`** as an Administrator.[cite: 2]
3. The script will automatically install the scripts and configure your `vlcrc` settings.[cite: 2]

### Manual Setup
If you are on a different OS or prefer manual installation, move the files to the following directories:

*   **`unofficial_vlc_intf.lua`** ➔ `VLC\lua\intf\`[cite: 2, 4]
*   **`unofficial_vlc_addons.lua`** ➔ `%APPDATA%\vlc\lua\sd\`[cite: 2, 3]
*   **`unofficial_vlc_playlist.lua`** ➔ `%APPDATA%\vlc\lua\playlist\`[cite: 1, 2]
*   **`unofficial_vlc_manager.lua`** ➔ `%APPDATA%\vlc\lua\extensions\`[cite: 2, 5]

---

## ⚙️ Configuration

The following settings are required in your VLC configuration (`vlcrc`) for the server to function:

*   `lua-intf=unofficial_vlc_intf`[cite: 2]
*   `extraintf=luaintf`[cite: 2]
*   `http-port=8181`[cite: 2]

---

## 📺 Usage

1.  **Manage Addons**: Open VLC and go to `View` > `Unofficial VLC Addons Manager` to add your Stremio manifest URLs.[cite: 5]
2.  **Browse Catalogs**: Navigate to `View` > `Playlist` > `Internet` > `Unofficial VLC Addons` to explore Movies and Series.[cite: 2, 3]
3.  **Web Dashboard**: Access settings and management at `http://127.0.0.1:8181` in any browser.[cite: 2, 4]
