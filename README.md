# Unofficial VLC Addons

This project allows you to use **Stremio addons** directly within VLC Media Player by hosting a local HTTP server and utilizing VLC's Lua scripting capabilities.

---

## 🛠 Project Components

*   **`unofficial_vlc_intf.lua`**: The core interface script that runs a local TCP HTTP server on port 8181 to handle addon logic and stream selection.
*   **`unofficial_vlc_addons.lua`**: A Service Discovery script that adds the "Unofficial VLC Addons" node to your VLC sidebar for browsing catalogs.
*   **`unofficial_vlc_playlist.lua`**: A playlist parser that handles the JSON data sent from the local server.
*   **`unofficial_vlc_manager.lua`**: A VLC Extension providing a graphical interface to add, remove, or toggle addons within VLC.
*   **`install.bat`**: A Windows batch script to automate the installation and configuration of all components.

---

## 🚀 Installation

### Automatic (Windows)
1. Download the script files into a single folder.
2. Run **`install.bat`** as an Administrator.
3. The installer will automatically locate your VLC installation, copy the files to the correct directories, and configure your settings.

### Manual Setup
If you prefer to install manually, move the files to these locations:
*   **`unofficial_vlc_intf.lua`** -> `VLC\lua\intf\`
*   **`unofficial_vlc_addons.lua`** -> `%APPDATA%\vlc\lua\sd\`
*   **`unofficial_vlc_playlist.lua`** -> `%APPDATA%\vlc\lua\playlist\`
*   **`unofficial_vlc_manager.lua`** -> `%APPDATA%\vlc\lua\extensions\`

---

## ⚙️ Configuration
To enable the server, the following settings must be applied to your VLC configuration (the installer handles this automatically):
*   `lua-intf=unofficial_vlc_intf`
*   `extraintf=luaintf`
*   `http-port=8181`

---

## 📺 Usage
1. **Manage Addons**: Go to `View` > `Unofficial VLC Addons Manager` to paste Stremio manifest URLs.
2. **Browse Content**: Go to `View` > `Playlist` > `Internet` > `Unofficial VLC Addons` to explore your added catalogs.
3. **Web Interface**: You can also manage settings and addons via your browser at `http://127.0.0.1:8181`.
