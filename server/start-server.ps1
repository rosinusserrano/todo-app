# Start the sync server on Windows.
#
#   .\server\start-server.ps1
#
# or double-click start-server.cmd, which just calls this without arguing about
# the execution policy.
#
# The server itself already prints the token and the addresses to type into the
# app. What this adds is everything around that: it can be run from anywhere,
# installs dependencies on first use, and - the part that actually bites on
# Windows - tells you when the firewall is the reason your phone cannot see a
# server that is definitely running.

[CmdletBinding()]
param(
    # Overrides the default 8787. The app must be given the same port.
    [int]$Port = $(if ($env:TODO_SYNC_PORT) { [int]$env:TODO_SYNC_PORT } else { 8787 }),

    # Refuse anything but this machine. Useful for a quick test; useless for a
    # phone, which is on the LAN by definition.
    [switch]$LocalOnly
)

$ErrorActionPreference = 'Stop'

# The server draws its summary in box-drawing characters, which come out as
# mojibake on a console still running a legacy codepage. This affects only this
# console window.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# The repo root is the parent of the directory holding this script, so the
# script works from any working directory.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Write-Section($text) {
    Write-Host ""
    Write-Host $text -ForegroundColor Cyan
}

# --------------------------------------------------------------- prerequisites

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host "node was not found on PATH." -ForegroundColor Red
    Write-Host "Install Node.js (LTS) from https://nodejs.org and run this again."
    exit 1
}
Write-Host "node $(node --version) - $($node.Source)" -ForegroundColor DarkGray

if (-not (Test-Path (Join-Path $root 'node_modules'))) {
    Write-Section "First run: installing dependencies (this takes a minute)"
    # better-sqlite3 is a native module, so this may compile.
    npm install
    if ($LASTEXITCODE -ne 0) {
        Write-Host "npm install failed - see the output above." -ForegroundColor Red
        exit 1
    }
}

# ------------------------------------------------------------------- firewall

# The single most common "it prints an address but my phone gets nothing":
# Windows blocks the inbound connection and nothing on either end says so.
# Adding a rule needs elevation, so this only ever *reports* - it prints the
# command rather than running it, since opening a port is not something a start
# script should do behind your back.
if (-not $LocalOnly) {
    $rule = Get-NetFirewallRule -DisplayName 'Todo Widget sync' -ErrorAction SilentlyContinue
    if (-not $rule) {
        Write-Section "Firewall"
        Write-Host "  No inbound rule for this server yet. If your phone cannot reach"
        Write-Host "  the address below, run this once in an " -NoNewline
        Write-Host "admin" -ForegroundColor Yellow -NoNewline
        Write-Host " PowerShell:"
        Write-Host ""
        Write-Host "    New-NetFirewallRule -DisplayName 'Todo Widget sync' ``" -ForegroundColor Yellow
        Write-Host "      -Direction Inbound -Action Allow ``" -ForegroundColor Yellow
        Write-Host "      -Protocol TCP -LocalPort $Port -Profile Private" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Profile Private keeps it to networks you have marked as private -"
        Write-Host "  your home wifi - rather than every coffee shop you connect to."
    }
}

# ---------------------------------------------------------------------- start

$env:TODO_SYNC_PORT = "$Port"
if ($LocalOnly) { $env:TODO_SYNC_HOST = '127.0.0.1' }

Write-Section "Starting - Ctrl+C to stop"
Write-Host "  The phone and this machine have to be on the same network." -ForegroundColor DarkGray
Write-Host "  Enter the address and token below in the app under the gear icon." -ForegroundColor DarkGray

npm run server
