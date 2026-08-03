# Build and install the Flutter widget on this machine, then start the sync
# server.
#
#   .\install-windows.ps1
#
# or double-click install-windows.cmd, which just calls this without arguing
# about the execution policy.
#
# `flutter build windows` leaves a bundle inside the repo, under
# app\build\... - running the app from there means the exe you use every day is
# the same one the next build overwrites, and "Start with Windows" points at a
# path inside a working tree. This copies the bundle out to a stable location
# under %LOCALAPPDATA% (so no elevation), gives it a Start-menu shortcut, and
# repoints the startup entry if it was aimed at the old exe.
#
# Your data is NOT in the install directory - it is in
# %APPDATA%\com.marco\todo_widget - so reinstalling never touches the database.

[CmdletBinding()]
param(
    # Where the app ends up. Per-user by design: no admin prompt, and the
    # startup entry is per-user anyway.
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\Todo Widget'),

    # Install whatever was built last instead of building again.
    [switch]$SkipBuild,

    # Also drop a shortcut on the desktop.
    [switch]$Desktop,

    # Install only - don't start the sync server.
    [switch]$NoServer,

    # Install only - don't launch the app afterwards.
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

# The repo root is the directory holding this script, so it works from any
# working directory.
$root = $PSScriptRoot
$appDir = Join-Path $root 'app'
$bundle = Join-Path $appDir 'build\windows\x64\runner\Release'
$exeName = 'todo_widget.exe'
$dataDir = Join-Path $env:APPDATA 'com.marco\todo_widget'

function Write-Section($text) {
    Write-Host ""
    Write-Host $text -ForegroundColor Cyan
}

# --------------------------------------------------------------- prerequisites

if (-not $SkipBuild) {
    $flutter = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutter) {
        Write-Host "flutter was not found on PATH." -ForegroundColor Red
        Write-Host "Install the Flutter SDK from https://docs.flutter.dev/get-started/install/windows"
        Write-Host "and run this again - or pass -SkipBuild to install an existing build."
        exit 1
    }
    Write-Host "flutter - $($flutter.Source)" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------- the build

if (-not $SkipBuild) {
    Write-Section "Building (first build of the day takes a few minutes)"
    Push-Location $appDir
    try {
        flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            Write-Host "The build failed - see the output above." -ForegroundColor Red
            exit 1
        }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path (Join-Path $bundle $exeName))) {
    Write-Host "No build to install at $bundle." -ForegroundColor Red
    Write-Host "Run this without -SkipBuild."
    exit 1
}

# ------------------------------------------------------------------- the copy

# The widget is always-on-top and lives in the tray, so it is almost certainly
# running right now - and a running exe cannot be overwritten. Closing it here
# bypasses the close guard (which refuses to quit with side thoughts pending);
# that is fine, nothing is lost, every change is already committed to SQLite.
$running = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Closing the running widget so its files can be replaced..." -ForegroundColor DarkGray
    $running | Stop-Process -Force
    # Give Windows a moment to actually release the file handles.
    Start-Sleep -Milliseconds 700
}

Write-Section "Installing to $InstallDir"

# robocopy /MIR deletes anything in the destination that is not in the source,
# which is what makes an upgrade clean (a plugin DLL dropped between versions
# would otherwise linger and get loaded). It also means pointing this at the
# wrong directory would empty it, so refuse anything that is not already ours.
if ((Test-Path $InstallDir) -and
    -not (Test-Path (Join-Path $InstallDir $exeName)) -and
    (Get-ChildItem -Force $InstallDir | Measure-Object).Count -gt 0) {
    Write-Host "$InstallDir exists, is not empty, and holds no $exeName." -ForegroundColor Red
    Write-Host "Refusing to mirror over it. Pass -InstallDir with somewhere else."
    exit 1
}

# robocopy uses exit codes as a bit field: under 8 is success, 8 and up is a
# real failure. It also writes to stdout in a way PowerShell should not parse.
robocopy $bundle $InstallDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Host "Copy failed (robocopy $LASTEXITCODE)." -ForegroundColor Red
    exit 1
}
$global:LASTEXITCODE = 0

$installedExe = Join-Path $InstallDir $exeName
Write-Host "  $installedExe" -ForegroundColor DarkGray

# -------------------------------------------------------------------- shortcuts

function New-Shortcut($path, $target) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($path)
    $link.TargetPath = $target
    $link.WorkingDirectory = Split-Path -Parent $target
    $link.Description = 'Todo Widget'
    $link.Save()
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Todo Widget.lnk'
New-Shortcut $startMenu $installedExe
Write-Host "  Start menu shortcut created" -ForegroundColor DarkGray

if ($Desktop) {
    New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Todo Widget.lnk') $installedExe
    Write-Host "  Desktop shortcut created" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- startup entry

# "Start with Windows" in Settings writes HKCU\...\Run with the path of the exe
# that was running at the time. If that was a build directory - or an older
# install - the entry now points at an exe this script just replaced or made
# stale, and it fails silently at the next logon. Only ever *repoint* an entry
# that already exists; turning startup on is the user's choice, in Settings.
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$runValue = 'todo_widget'
$existing = (Get-ItemProperty -Path $runKey -Name $runValue -ErrorAction SilentlyContinue).$runValue
if ($existing) {
    $wanted = """$installedExe"""
    if ($existing.Trim('"') -ne $installedExe) {
        Set-ItemProperty -Path $runKey -Name $runValue -Value $wanted
        Write-Host "  Repointed the 'Start with Windows' entry at the new exe" -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------------------ done

Write-Section "Installed"
Write-Host "  App    $InstallDir"
Write-Host "  Data   $dataDir" -NoNewline
if (Test-Path (Join-Path $dataDir 'todo.db')) {
    Write-Host "  (existing database kept)" -ForegroundColor DarkGray
} else {
    Write-Host ""
}

if (-not $NoLaunch) {
    Start-Process -FilePath $installedExe -WorkingDirectory $InstallDir
    Write-Host "  Launched." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------- sync server

# In its own window, because the server runs in the foreground until Ctrl+C and
# this script should not hold the console hostage. start-server.ps1 prints the
# address and token to type into the app, so that window is worth reading.
if (-not $NoServer) {
    $serverScript = Join-Path $root 'server\start-server.ps1'
    if (Test-Path $serverScript) {
        Write-Section "Starting the sync server in a new window"
        Write-Host "  Its window prints the address and token for the app's gear icon." -ForegroundColor DarkGray
        Start-Process powershell -ArgumentList @(
            '-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', "`"$serverScript`""
        )
    } else {
        Write-Host "server\start-server.ps1 not found - skipping the server." -ForegroundColor Yellow
    }
}
