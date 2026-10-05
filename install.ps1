# Antigravity CLI Statusline Installer for Windows (PowerShell)
# Usage: irm https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

Write-Host "=== Antigravity CLI Statusline Installer (Windows PowerShell) ===" -ForegroundColor Cyan

# 1. Target directory
$targetDir = Join-Path $HOME ".gemini\antigravity-cli"
$scratchDir = Join-Path $targetDir "scratch"

if (-not (Test-Path $scratchDir)) {
    Write-Host "Creating directory: $scratchDir" -ForegroundColor Gray
    New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null
}

# 2. Check Python
Write-Host "Checking Python..." -ForegroundColor Gray
$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        $pythonCmd = $found.Source
        break
    }
}

if (-not $pythonCmd) {
    Write-Host "❌ Error: Python is not found in PATH. Please install Python to use this statusline." -ForegroundColor Red
    exit 1
}
Write-Host "✅ Python found: $pythonCmd" -ForegroundColor Green

# 3. Copy or Download statusline.py
$statuslineDest = Join-Path $scratchDir "statusline.py"
$localSource = Join-Path $PSScriptRoot "statusline.py"

if ($PSScriptRoot -and (Test-Path $localSource)) {
    Write-Host "Copying local statusline.py to $statuslineDest..." -ForegroundColor Gray
    Copy-Item -Path $localSource -Destination $statuslineDest -Force
} else {
    Write-Host "Downloading statusline.py from GitHub..." -ForegroundColor Gray
    $repoUrl = "https://raw.githubusercontent.com/es-studio/agy-cli-statusline/main/statusline.py"
    Invoke-WebRequest -Uri $repoUrl -OutFile $statuslineDest -UseBasicParsing
}
Write-Host "✅ statusline.py installed." -ForegroundColor Green

# 4. Update settings.json
$settingsPath = Join-Path $targetDir "settings.json"
Write-Host "Configuring settings.json..." -ForegroundColor Gray

$settings = @{}
if (Test-Path $settingsPath) {
    try {
        $content = Get-Content -Path $settingsPath -Raw -Encoding UTF8
        $settings = $content | ConvertFrom-Json -AsHashtable
    } catch {
        $settings = @{}
    }
}

if (-not $settings.ContainsKey("statusLine")) {
    $settings["statusLine"] = @{}
}

# Format normalized command string with forward slashes for clean JSON
$normPython = $pythonCmd -replace '\\', '/'
$normScript = $statuslineDest -replace '\\', '/'

$settings["statusLine"]["type"] = "command"
$settings["statusLine"]["command"] = "$normPython $normScript"
$settings["statusLine"]["enabled"] = $true

$newJson = $settings | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($settingsPath, $newJson, [System.Text.Encoding]::UTF8)

Write-Host "✅ Statusline configuration saved to settings.json." -ForegroundColor Green
Write-Host "🎉 Installation completed successfully!" -ForegroundColor Cyan
Write-Host "Please restart your Antigravity CLI (agy) session to see your new statusline." -ForegroundColor Yellow
