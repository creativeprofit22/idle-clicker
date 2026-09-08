# Project instructions

- This is a Godot 4.7.2 Standard (GDScript) project, not .NET. See README.md for local setup and detailed verification requirements.
- Import / script check: `godot --headless --path . --editor --quit`.
- Headless tests: `godot --headless --path . --script tests/run_tests.gd`.
- Failure-path verification: `godot --headless --path . --script tests/run_tests.gd -- --force-failure` must exit 1 with exactly one intentional failure; rerun normally afterward.
- Graphical smoke tests: `godot --path . --script tests/scene_smoke.gd`. Keep the window focused and unminimized; these remain a manual gate, not a headless substitute.
- Missing summaries, parse errors, timeouts, or nonzero normal exits are failures. Never weaken checks or focus/suspension behavior to pass them.
- No separate lint tool, dependency install, or export build is configured. Import checks scripts; do not invent export presets.
- CI lives in `.github/workflows/` and must stay green. It targets GitHub's default branch, `main`, and uses one cached Linux job. No artifact uploads.
- Keep generated `.godot/` data, screenshots, logs, credentials, and local environment files out of commits.
- Never commit with `--no-verify`.
