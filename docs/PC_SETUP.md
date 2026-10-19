# Setting up BLACKVEIN on a fresh Windows PC

Everything needed to get back to work after reinstalling Windows. The project lives in `E:\BLACKVEIN`
(the source of truth is GitHub: https://github.com/La2o/BlackVein, branch `main`).

## 1. Restore the tools from `_pc_backup` (no downloads needed)

`E:\BLACKVEIN\_pc_backup\` (not in git) holds copies made before the format:

| Folder | Put it back at |
|---|---|
| `godot\` (Godot 4.5-stable, `Godot_v4.5-stable_win64.exe` + `_console.exe`) | `%LOCALAPPDATA%\Programs\Godot\` |
| `export_templates\4.5.stable\` | `%APPDATA%\Godot\export_templates\4.5.stable\` |
| `save\blackvein_save.json`, `save\settings.cfg` (your game save and settings) | `%APPDATA%\Godot\app_userdata\BLACKVEIN\` |

In PowerShell:

```
$b = "E:\BLACKVEIN\_pc_backup"
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Programs\Godot", "$env:APPDATA\Godot\export_templates\4.5.stable", "$env:APPDATA\Godot\app_userdata\BLACKVEIN" | Out-Null
Copy-Item "$b\godot\*" "$env:LOCALAPPDATA\Programs\Godot\"
Copy-Item "$b\export_templates\4.5.stable\*" "$env:APPDATA\Godot\export_templates\4.5.stable\"
Copy-Item "$b\save\*" "$env:APPDATA\Godot\app_userdata\BLACKVEIN\"
```

If the backup is gone: Godot 4.5-stable (Windows, standard, not .NET) and
`Godot_v4.5-stable_export_templates.tpz` come from the godotengine/godot GitHub release `4.5-stable`.
From the .tpz (a zip) only `windows_release_x86_64.exe`, `linux_release.x86_64` and `version.txt` are
needed.

## 2. Install

- **Git for Windows** (includes Git Bash). The repo's own config already has the author
  (`La2o`, `25359942+La2o@users.noreply.github.com`) and the `origin` remote.
- **GitHub CLI** (`gh`), then `gh auth login` (needed to push and to manage releases).
- **Python 3** (only for `tools/make_sounds.py` and the patch scripts; the game doesn't need it).
- **Claude Code** (desktop app or CLI). Open the session in `E:\BLACKVEIN`: it reads `CLAUDE.md` first.

## 3. Check it works

```
"%LOCALAPPDATA%\Programs\Godot\Godot_v4.5-stable_win64_console.exe" --headless --path E:\BLACKVEIN --import
"%LOCALAPPDATA%\Programs\Godot\Godot_v4.5-stable_win64_console.exe" --headless --fixed-fps 60 --quit-after 80000 --path E:\BLACKVEIN res://tests/test_runner.tscn
```

The second command must end with `0 failed`. The playable build is `E:\BLACKVEIN\export\windows\BLACKVEIN.exe`
(or `PLAY.bat` next to it).
