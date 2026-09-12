# Phase 0 — Project Setup & Pixel-Perfect Config

**Goal:** an empty but correctly-configured Godot 4 project that boots to a blank scene,
with pixel-perfect rendering, folder structure, and assets imported. No gameplay yet.

## Do

1. Confirm this is a Godot 4.x project (`project.godot` present). If not, tell me to create the
   project in the Godot editor first — you cannot create the editor project from here, but you
   can write all the config and scripts.
2. Create the folder structure from `CLAUDE.md` under `res://` (empty dirs are fine with a
   `.gdignore` or a placeholder).
3. Configure **pixel-perfect rendering** in `project.godot`:
   - Rendering → Textures → Canvas Textures → Default Texture Filter = **Nearest**
   - Rendering → 2D → **Snap 2D Transforms to Pixel** = on, **Snap 2D Vertices to Pixel** = on
   - Display → Window → Stretch → Mode = `viewport`, Aspect = `keep`
   - Set a base viewport resolution (suggest **640×360**, integer-scales cleanly to 1080p/4K)
4. Set the default clear/background colour to a soft sky tone (placeholder).
5. Create `CREDITS.md` at the root using the attribution snippet in `docs/ASSETS.md`.
6. Create `scenes/main/Main.tscn` with a root `Node2D` named `Main`, set as the **main scene**.
   For now it just holds a `Label` saying "Island — Phase 0 OK" centered on screen.
7. **Asset import:** the raw art lives outside the project. Tell me exactly which files to copy
   into which `res://assets/...` folders (reference `docs/ASSETS.md`). Once copied, ensure the
   import settings are pixel-art (Nearest filter). If you can, write/import a shared import preset.

## Definition of done
- Project boots to the "Phase 0 OK" label, crisp (no blur) at multiple window sizes.
- Folder structure and `CREDITS.md` exist.
- I can see where assets should go.

## Do NOT
- Add any autoloads yet.
- Add player, world, or any gameplay.
- Import every asset blindly — only set up the folders + import config; we pull assets per phase.

When done, update `docs/ROADMAP.md` (tick Phase 0) and the "Current status" in `CLAUDE.md`.
