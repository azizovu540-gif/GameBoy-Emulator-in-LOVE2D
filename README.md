# 🕹️ Custom Lua Game Boy Emulator from Scratch (LÖVE / Love2D)

A fully custom, high-performance 8-bit Game Boy (DMG-01) emulator written entirely from scratch in Lua using the LÖVE framework. Optimized for LuaJIT.

Unlike many modern hobby projects, **this emulator features a 100% custom CPU core and PPU built entirely from the ground up** without relying on third-party emulation libraries or pre-made instruction decoders.

---

## 🚀 Features

- **100% Custom CPU Core:** Complete emulation of the Sharp LR35902 processor, including all 256 base opcodes, full prefix CB bit-shift/rotation tables, and proper CPU flags handling ($Z, N, H, C$).
- **Pixel-Accurate PPU:** Real-time rendering of all three hardware graphical layers: Background, Sprites (OBJ with hardware DMA transfer), and Window (with signed tile addressing support).
- **Smooth Pixel Scrolling:** Implemented accurate hardware scrolling ($SCX / SCY$) providing buttery-smooth pixel movement instead of jagged blocky tile-snapping.
- **Memory Bank Controller (MBC1):** Built-in memory management supporting heavy commercial titles up to 128KB/512KB (e.g., *Super Mario Land*).
- **Universal Gamepad Support:** Powered by SDL2 via LÖVE, allowing plug-and-play compatibility with any gamepad (Xbox, PlayStation, Nintendo Switch) along with customizable keyboard mapping.
- **Built-in ROM Selector:** Features a custom retro-styled boot menu that automatically scans the directory for `.gb` files and switches games on the fly.

---

## 🎮 Controls

| Game Boy Key | Keyboard Mapping | Universal Gamepad Mapping |
| :--- | :--- | :--- |
| **D-Pad (Arrows)** | `Up / Down / Left / Right` | Left Analog Stick / D-Pad |
| **Button A** | `Z` | `A` (Xbox) / `Cross` (PS) / `B` (Switch) |
| **Button B** | `X` | `X` (Xbox) / `Square` (PS) / `Y` (Switch) |
| **START** | `Space` (Пробел) | `START` |
| **SELECT** | `Right Shift` | `BACK / SELECT` |
| **Menu Exit** | `Esc` | Returns back to ROM Selector |

---

## ⚙️ How to Run

1. Download and install **[LÖVE Framework](https://love2d.org)** for your OS (Windows, macOS, Linux).
2. Clone this repository or download the source code.
3. Drop your legal Game Boy ROM files (`.gb`) directly into the project folder.
4. Run the project directory using LÖVE or execute the standalone `.love` distribution bundle.

---

## 🛠️ Project Structure

- `main.lua` — Core emulator loop, timing synchronization, and LÖVE callbacks.
- `cpu.lua` — Custom instruction matrix and execution loop.
- `mmu.lua` — Hardware memory map, I/O registers, inline DMA copy, and MBC1 bank switching.
- `ppu.lua` — Video rendering engine, scanline buffer assembler, and tile data decoder.
- `joypad.lua` — Unified hardware keyboard and gamepad polling module.

---

## 📝 License
This project is open-source. Feel free to explore the custom hardware logic!
