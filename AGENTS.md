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

## Windows campaign graphical verification

- Default to the verified native Windows driver for unattended campaign smokes, rather than the direct Godot-setter route with its known native-focus failure. Invoke the Python driver, not the internal `--native-window-driver` handshake flag.

| Scenario | Command | Driver deadline | Caller timeout |
|---|---|---|---|
| Focus-only | `python tests/windows_campaign_driver.py focus-only` | 12 seconds | 20 seconds |
| Full campaign | `python tests/windows_campaign_driver.py campaign` | 65 seconds | 75 seconds |
| Full defense | `python tests/windows_campaign_driver.py defense` | 65 seconds | 75 seconds |

- Require complete summaries with zero failures, child and driver exits 0, and cleanup confirming the child was reaped and output reader joined. Missing summaries, parse errors, timeouts, failed assertions, incomplete scenarios, or nonzero exits are failures; report unreached checks explicitly. Inspect captured screenshots for full scenarios as described in README.md.
- Preserve PID/window-scoped native actions, all assertions, strict focus/suspension gates, and existing deadlines. Never loop on unchanged failures: retain the failed result and diagnose or report the blocker before another run. Do not rerun unchanged code for a documentation-only handoff.
- Automated driver evidence does not replace the required physical manual gate. That gate remains **pending**, not waived or passed. Request physical interaction only when this required gate genuinely blocks the requested milestone; do not request it for unattended driver runs.
- All existing import, headless, forced-failure, graphical, and CI verification requirements above remain in force.
