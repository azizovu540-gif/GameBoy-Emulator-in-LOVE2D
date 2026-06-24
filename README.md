# 🕹️ Custom Lua Game Boy Emulator from Scratch (LÖVE / Love2D)

A fully custom, high-performance 8-bit Game Boy (DMG-01) emulator written entirely from scratch in Lua using the **LÖVE framework**. This project features a completely custom CPU core, PPU layout, and an integrated audio subsystem.

Optimized for **LuaJIT** and ready for both classic games and unlicensed homebrew/bootlegs.

---

## 📸 Screenshots

<p align="center">
  <img src="test.png" width="31%" alt="Tetris Screen" />
  <img src="zelda.png" width="31%" alt="Zelda Title Screen" />
  <img src="zelda2.png" width="31%" alt="Zelda Gameplay" />
</p>

<p align="center">
  <em>Running "Tetris" and "The Legend of Zelda: Link's Awakening" smoothly at 60 FPS with full audio, input, and save state support.</em>
</p>

---

## 🚀 Features (v1.3 Update)

* **💾 Save States System:** Instantly save and load your exact game state at any microsecond. Perfect for long adventures like Zelda!
* **🎵 Multi-Channel APU (Audio Core):** Built-in stereo synthesis simulating Square 1, Square 2, and Wave RAM channels. Experience crunchy, raw retro bass and sound effects!
* **🧠 All-Round Mapper Compatibility:** Smart dynamic cartridge detection. Fully supports **MBC1, MBC2, MBC3, MBC5**, and automatically fixes broken headers in unlicensed bootleg ROMs (like *Sonic 3D Blast 5*).
* **🏃 Dynamic Frame Synchronization:** Synchronizes CPU cycles perfectly with LÖVE's `deltaTime` and hardware V-Sync. No screen tearing and 0 input lag thanks to JIT optimizations!
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
| **Quick Save** | `F5` | `L1 + Y` (Hold L1 and press Y) |
| **Quick Load** | `F6` | `L1 + X` (Hold L1 and press X) |
| **Exit to Menu** | `Escape` | — |

---

## 📜 Legal & License

This emulator is an educational project built for reverse-engineering study purposes. It contains 100% custom codebase and **does not** include or distribute any copyrighted Nintendo digital assets, BIOS, or commercial game ROMs.

Feel free to explore the custom hardware logic, submit issues, or fork the project! ⭐
