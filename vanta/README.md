# VANTA: Realms Beyond (scripts)

`src/` holds every script from the `Vanta.rbxl` place, one file per script. The folders mirror the Explorer:
`ReplicatedStorage/Shared/...`, `ServerScriptService/Server/...`, and so on. Models, meshes, animations and other
assets stay in the place file.

- The capital, the forest and the hideout: [docs/CITY.md](docs/CITY.md)

## Tools

The tools run outside Studio with [Lune](https://github.com/lune-org/lune) 0.10 and Python 3 (`pip install lz4
zstandard pillow`). Run them from this folder.

| Command | What it does |
| --- | --- |
| `lune run tools/run-tests.luau` | Runs `ServerStorage.Tests.RunAll`, the same specs Studio runs |
| `lune run tools/check-layout.luau` | Checks the city layout with `LayoutRules` |
| `lune run tools/inspect-city.luau` | Builds the city and checks every doorway, stair and landing for obstructions |
| `lune run tools/build-city.luau [--rbxm]` | Builds the city and counts what it made; `--rbxm` writes `build/City.rbxm` |
| `lune run tools/dump-layout.luau` then `python3 tools/render_plan.py` | Draws the master plan to `build/master-plan.png` |
| `python3 tools/patch_place.py Vanta.rbxl Out.rbxl --streaming` | Writes `src/` into a copy of the place (see below) |
| `python3 tools/sourcemap.py > sourcemap.json` | Writes a Rojo-style sourcemap, for `luau-lsp analyze` |

`tools/harness.luau` builds a DataModel from `src/` and runs modules with a Roblox-like `require`. Specs that need
live services (DataStores, players) still have to run in Studio.

## Getting changes into the place

`tools/patch_place.py` copies the place chunk for chunk and changes only what `src/` changed:

- it updates the `Source` of every script whose file differs
- it adds scripts that exist only as files
- with `--streaming`, it turns on `Workspace.StreamingEnabled`

Meshes, animations and every other property are left untouched. Open the result in Studio and check it before
publishing.
