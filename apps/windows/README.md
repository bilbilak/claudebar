# ClaudeBar — Windows tray app

System-tray app that shows your Claude.ai Max-plan session and weekly usage, mirroring the [GNOME extension](../claudebar-gnome-extension).

- Tray icon with two stacked bars (current 5-hour session + 7-day weekly).
- Right-click (or left-click) for a menu with percentages, reset times, refresh, and link to claude.ai.
- Sign in with Claude via OAuth (PKCE); tokens are encrypted with DPAPI (user scope) in `%APPDATA%\ClaudeBar\tokens.bin`.
- Configurable poll interval and color thresholds.

## Requirements

- Windows 10 (1809) or Windows 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) for building

## Build

```pwsh
dotnet restore
dotnet build -c Release
dotnet run -c Release
```

Or publish a self-contained single-file build:

```pwsh
dotnet publish -c Release -r win-x64 --self-contained false -o publish
publish\ClaudeBar.exe
```

## Sign in

1. Launch `ClaudeBar.exe` — a tray icon with two bars appears near the clock.
2. Right-click the icon → **Settings…**
3. On the **Account** tab, click **Sign in with Claude**. Your default browser opens to claude.ai.
4. Complete sign-in. The tab will say "Signed in" and the bars will update within a minute.

Token storage:

- `%APPDATA%\ClaudeBar\tokens.bin` — DPAPI-encrypted, user scope
- `%APPDATA%\ClaudeBar\settings.json` — preferences (plain JSON)

## Uninstall

```pwsh
Remove-Item -Recurse "$env:APPDATA\ClaudeBar"
```

Then delete the executable or the published folder.

## Auto-start at login (optional)

Copy a shortcut to the Startup folder:

```pwsh
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ClaudeBar.lnk")
$lnk.TargetPath = "C:\Path\To\ClaudeBar.exe"
$lnk.Save()
```
