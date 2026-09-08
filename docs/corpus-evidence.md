# Engine and production-pipeline evidence handoff

Research date: 2026-09-07. No engine or production pipeline selected. Repository indexing was approved for five candidates; four succeeded. No game code, engine, or dependency was installed or executed.

## Confirmed brief

Read `game-design.md` and `first-playable.md` together. The user's latest direction supersedes their deferred-art language: the finished historical-armies idle game should be polished 2D with cinematic-anime art direction, offline single-player, eventually released on Android. The first prototype still uses placeholders. There is no selected implementation language, framework, engine, or entry point; the project is documentation-only.

Central research topics: deterministic automatic combat and touch commands; progression and selective-retention prestige; reliable local saves and bounded closed-app rewards; layered 2D animation, camera choreography and effects; Android lifecycle, performance and automated behavior tests. Compare Unity (C#), Godot (GDScript/C#), and Defold (Lua with native engine/extensions) without inferring a winner from corpus coverage.

## Approved set and actual indexing

Tag: `idle-clicker`. Four indexed repositories, 901 searchable files; overall corpus now 119 repositories. `defold/defold` failed twice with `incomplete deflate stream`; do not describe it as indexed. Other repositories in that partially failed batch succeeded, verified with the tag-filtered repository listing.

| Repository | GitHub stars / latest push observed | Indexed revision / files | License and evaluation role |
| --- | --- | --- | --- |
| [godotengine/godot-demo-projects](https://github.com/godotengine/godot-demo-projects) | 9,488 / 2026-08-25 | `0db80ca5fd22b9a40e05b9bc1e00af867fb7c712` / 34 | MIT baseline; animation, layers, particles, input and asset-import examples. Individual asset notices still apply. |
| [Unity-Technologies/2d-techdemos](https://github.com/Unity-Technologies/2d-techdemos) | 1,016 / 2026-03-13 | `6593d544df2ea598e51f5cf1d7165d5ed42ceba7` / 18 | MIT baseline; tile environments, sorting and camera examples, not a cinematic-animation production template. Unity engine/package terms are separate. |
| [defold/defold](https://github.com/defold/defold) | 6,293 / 2026-09-07 | Download failed | Custom Defold License: not MIT; prohibits commercializing the work as a game-engine product. Evaluate lean alternative, Android bundling and tests; no project-specific performance result. |
| [pmotschmann/Evolve](https://github.com/pmotschmann/Evolve) | 1,236 / 2026-09-07 | `3436358dcd03d9f9e071d51ea071e0a78c0322e4` / 53 | MPL-2.0; browser-game progression and reset/save references, not an Android engine template. Review file-level source obligations before copying. |
| [defold/extension-rive](https://github.com/defold/extension-rive) | 73 / 2026-09-05 | `22be59a370162c0df8b6c44fcaff1e28d3e864ef` / 796 | MIT wrapper baseline; bundled runtime and assets require their own notices. README credits an achievement asset under CC-BY 4.0. |

Metadata was checked through GitHub repository APIs and source trees. All five were unarchived. Push dates are activity signals, not proof of recent default-branch maintenance or successful tests. Corpus listings report older dates for Unity (2026-02-11) and Evolve (2026-06-19); retain exact indexed revisions rather than equating latest repository push with indexed code freshness. No CI run or Android device benchmark was executed.

## Corpus search → file reads actually completed

- **Godot:** literal `AnimatedSprite2D` → `mono/dodge_the_creeps/Player.cs:1–88`. Shows action input, delta-based movement, animation switching, clamping and deferred collision disabling. This is a small C# example, not cinematic choreography or an idle simulation. The corpus retained only 34 of 4,071 source-tree files: its file listing contains no GDScript, scene resources or art. Do not interpret that omission as an engine limitation.
- **Unity:** literal `Camera` → `Assets/Tilemap/IsometricZAsY/Scripts/BasicCameraFollow.cs:1–27`. Shows basic target following, not cinematic sequencing. The sample recreates its damping velocity each frame; do not promote this sample to a proven production camera without checking the API and testing behavior. Only 18 of 949 tree files were retained, excluding the environmental scenes and most asset evidence.
- **Prestige and saving:** literal `localStorage` → `src/vars.js:1–45`; literal `export function` scoped to `src/resets.js` → `src/resets.js:1–88`. `warhead` saves a pre-reset backup, computes prestige, retains selected fields, resets common state, writes the new save and reloads. Useful order-of-operations evidence, but the shown path does not establish atomic transactions, schema validation, corruption recovery or storage-error handling. Do not copy its analytics or reload-based browser architecture into the offline game.
- **Rive:** literal `StateMachine` → `defold-rive/api/rive.lua:100–170` (API declarations, not executable integration proof). Follow-up literal `instantiateStateMachineNamed` → `defold-rive/commonsrc/file.cpp:365–445` confirms native handle creation/deletion, default-state-machine fallback, view-model binding and command processing. This is actual integration code rather than assuming an animation authoring tool is a runtime.

## Complementary upstream evidence, not necessarily searchable locally

Godot source tree includes `2d/skeleton/player/player.tscn`, `2d/skeleton/level/parallax_background.tscn`, `2d/particles/particles.tscn`, `2d/platformer/gui/touch_button_jump.webp`, and `3d/occlusion_culling_mesh_lod/room.blend.import`. These paths were verified in the GitHub tree, not all content-read or rendered. Read their contents directly before relying on their behavior. The README states that master targets Godot development master; use a matching stable demo branch when testing an engine release.

Godot's [JSON serialization sample](https://github.com/godotengine/godot-demo-projects/blob/0db80ca5fd22b9a40e05b9bc1e00af867fb7c712/loading/serialization/save_load_json.gd) was read upstream. It directly opens the destination for writing and loads parsed fields without demonstrated failure recovery. It is serialization teaching material, not a reliable-save design for this game's acceptance scenarios.

Unity's tree includes `Assets/Tilemap/IsometricZAsY/Scripts/CustomAxisSortCamera.cs` and `Assets/Tilemap/Normal Mapping (Built-in)/Material/Shader/NormalMappedTile.shader`. The README identifies tilemap demos and a Unity 2021.1+ baseline. A recent repository push does not prove the older built-in shader path is the right modern rendering pipeline. Skeletal animation, cinematic sequencing, touch UI, Android export and automated game tests remain incomplete Unity coverage in this shortlist.

Defold's tree includes `README_ANDROID.md`, `build_tools/build_android.py`, `build_tools/waf_tests.py`, and `com.dynamo.cr/com.dynamo.cr.bob.test/src/com/dynamo/bob/bundle/test/AndroidBundlerTest.java`. Paths were verified, but the engine download failed and these implementations have not been corpus-read. The engine source is a relatively large download; no claim about small runtime memory, battery use or package size follows from selecting it as the lean candidate.

The Rive extension README explicitly supports Android arm64, not armv7; WebGL1 and consoles are also excluded. Its tree contains `ci/tests/android/test.sh` and `ci/rendertest/android/run.sh`. The read `.github/workflows/device-tests.yml` content demonstrates HTML5 build/test automation; Android script existence alone does not prove current Android CI passes. Device performance and rendering compatibility must still be measured.

## Rive versus Blender

**Rive:** interactive vector animation/state-machine runtime candidate for HUDs, feedback and potentially characters. The Defold native integration above is concrete evidence. Also inspected upstream: [rive-app/rive-unity-examples](https://github.com/rive-app/rive-unity-examples), 60 stars, pushed 2026-01-22, unarchived. Its README points to the actual Rive Unity package and describes artboard input/events and render-to-texture examples. Tree evidence includes `demos/Assets/Demos/Buildings/Scripts/CinemachineSpinCamera.cs` and `getting-started/Assets/Demos/HealthBar/RiveFiles/quick_start_health_bar.riv`. This repository was not approved for indexing and was not added. A root license was not established: treat its code/art as inspection or visual references, not reusable assets. No Godot Rive integration was verified.

**Blender:** asset-authoring/import stage, not an interchangeable in-game UI runtime. The Godot demo tree supplies actual `.blend` and `.blend.import` examples. Godot's upstream importer is `modules/gltf/editor/editor_scene_importer_blend.cpp`; its [official importer contract](https://docs.godotengine.org/en/stable/classes/class_editorsceneformatimporterblend.html) describes conversion through glTF 2.0. This establishes a 3D asset-import route, not an anime 2D sprite-sheet, Grease Pencil or layered-background production pipeline. Such a pipeline is a possible experiment, not verified coverage. Unity/Defold Blender import workflows were not validated here.

## Decision boundary and next evidence

This is the smallest approved complementary set, not complete production proof. It covers gameplay reset patterns, basic rendering examples and one real animation runtime. It does not yet establish polished cinematic-anime art, robust crash-safe local saves, equivalent modern animation pipelines across engines, automated idle-game acceptance tests or Android frame-time/memory budgets. Repository assets are technical examples or visual references until their individual licenses are checked; no candidate is an approved art pack.

For later engine selection, use the same placeholder battle, touch command and layered animated scene in each candidate; compare export friction, input/lifecycle behavior, frame times, memory and testability. Save validation, interruption recovery and exact-once rewards need dedicated acceptance tests. These are evaluation criteria, not permission to implement prototypes now.

Concrete next corpus query: `steroids` action `search`, repo `pmotschmann/Evolve`, pattern `calcPrestige`, fixed `true`; then `show` its implementation and compare reset ordering against `first-playable.md`. Use direct upstream reads for Godot GDScript/scenes and shader/assets omitted by indexing. Retry the already-approved Defold engine download later; no substitute repository was silently added.
