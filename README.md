# 🕹️ Custom Lua Game Boy Emulator from Scratch (LÖVE / Love2D)

A fully custom, high-performance 8-bit Game Boy (DMG-01) emulator written entirely from scratch in Lua using the **LÖVE framework**. This project features a completely custom CPU core, PPU layout, and a newly integrated audio subsystem.

Optimized for **LuaJIT** and ready for both classic games and unlicensed homebrew/bootlegs.

---

## 📸 Screenshots

![Tetris](test.png)
*Running the absolute classic "Tetris" smoothly with the custom v1.1 audio engine playing the iconic tune.*

---

## 🚀 Features (v1.1 Update)

* **🎵 Multi-Channel APU (Audio Core):** Built-in stereo synthesis simulating Square 1, Square 2, and Wave RAM channels. Experience crunchy, raw retro bass and sound effects!
* **🧠 All-Round Mapper Compatibility:** Smart dynamic cartridge detection. Fully supports **MBC1, MBC2, MBC3, MBC5**, and automatically fixes broken headers in unlicensed bootleg ROMs (like *Sonic 3D Blast 5*).
* **🏃 Dynamic Frame Synchronization:** Synchronizes CPU cycles perfectly with LÖVE's `deltaTime` and hardware V-Sync. Say goodbye to screen tearing and input lag!
* **🎮 Accurate Hardware Input:** Joypad matrix re-engineered directly from official Game Boy hardware registers. Includes plug-and-play gamepad support.
* **📂 Retro ROM Selector:** Features a clean, custom retro-styled boot menu that automatically scans the directory for your `.gb` files.

---

## 🛠️ Installation & How to Play

1. Download and install the **[LÖVE Framework](https://love2d.org)** for your OS.
2. Clone or download this repository to your computer.
3. Drop your legal Game Boy ROM files (`.gb`) directly into the project folder.
4. Run the project directory using LÖVE:
   ```bash
   love .
   ```

### ⌨️ Default Controls

| Game Boy Button | Keyboard Key | Gamepad Button (Xbox) |
| :--- | :--- | :--- |
| **D-PAD (Move)** | Arrow Keys (`Up/Down/Left/Right`) | Left Stick / D-Pad |
| **Button A** | `Z` | `A` |
| **Button B** | `X` | `X` |
| **START** | `Space` (Spacebar) | `Start` |
| **SELECT** | `Right Shift` | `Back / Select` |
| **Exit to Menu** | `Escape` | — |

---

## 📜 Legal & License

This emulator is an educational project built for reverse-engineering study purposes. It contains 100% custom codebase and **does not** include or distribute any copyrighted Nintendo digital assets, BIOS, or commercial game ROMs.

Feel free to explore the custom hardware logic, submit issues, or fork the project! ⭐
