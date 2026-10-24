<#
.SYNOPSIS
    Builds the Typist Windows installers on this PC (64-bit Windows, x64).

.DESCRIPTION
    One script, run once per machine and again whenever you want a fresh build:
      1. installs the build tools with winget (skipped if already present),
      2. clones (or updates) the Typist repository,
      3. builds the .exe (NSIS) and .msi installers,
      4. copies them to Desktop\Typist-installers and opens that folder.

    It mirrors the GitHub Actions Windows build (.github/workflows/build.yml):
    long paths on, a short target directory for whisper-rs-sys, the Vulkan SDK,
    and the same CPU-compatibility flags, so the result matches that build.

    Installing the tools accepts their licence agreements through winget
    (Visual Studio Build Tools, Rust, Bun, Git, CMake, LLVM, Vulkan SDK).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build-windows.ps1

.PARAMETER Dir
    Where the repository lives (cloned there if missing). Default: %USERPROFILE%\Typist.
.PARAMETER Branch
    Branch to build. Default: typist-main.
.PARAMETER SkipInstall
    Skip the tool installation step (tools already installed).
.PARAMETER Native
    Optimise for THIS PC's CPU (faster Whisper) instead of building a portable
    installer. Don't share a Native build: it can crash on older CPUs.
#>
param(
    [string]$Dir = (Join-Path $env:USERPROFILE "Typist"),
    [string]$Branch = "typist-main",
    [switch]$SkipInstall,
    [switch]$Native
)

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/Joaoha/Typist.git"

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "`nERROR: $text" -ForegroundColor Red; exit 1 }

# Re-read PATH and the SDK variables that installers just wrote, so tools
# installed by this run are usable without opening a new terminal.
function Update-SessionEnv {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user;$env:USERPROFILE\.cargo\bin;$env:USERPROFILE\.bun\bin"
    foreach ($name in "VULKAN_SDK") {
        $value = [Environment]::GetEnvironmentVariable($name, "Machine")
        if (-not $value) { $value = [Environment]::GetEnvironmentVariable($name, "User") }
        if ($value) { Set-Item "env:$name" $value }
    }
}

function Require($command, $hint) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        Fail "'$command' is not available. $hint"
    }
}

# --- Preconditions ---------------------------------------------------------

if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64") {
    Fail "This script builds on 64-bit Intel/AMD Windows (x64). This PC reports '$env:PROCESSOR_ARCHITECTURE'."
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # Long paths and Visual Studio Build Tools need administrator rights.
    Write-Host "Restarting as administrator (Windows will ask for permission)..."
    # -NoExit keeps the new window open so the result (or error) stays readable.
    $forward = @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"",
        "-Dir", "`"$Dir`"", "-Branch", $Branch)
    if ($SkipInstall) { $forward += "-SkipInstall" }
    if ($Native) { $forward += "-Native" }
    Start-Process powershell -Verb RunAs -ArgumentList $forward
    exit 0
}

# --- 1. Build tools --------------------------------------------------------

if (-not $SkipInstall) {
    Require winget "Install 'App Installer' from the Microsoft Store, then run this again."

    Step "Enabling long file paths (whisper.cpp's build paths exceed 260 characters)"
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
        -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force | Out-Null

    # First: Rust's installer offers to install Visual Studio itself when it
    # finds no C++ compiler, which a silent install must never reach.
    Step "Installing Visual Studio 2022 Build Tools (C++ compiler + Windows SDK; this one is slow)"
    winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --accept-package-agreements `
        --accept-source-agreements --override `
        "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

    $packages = @(
        @{ Id = "Git.Git"; Name = "Git" },
        @{ Id = "Rustlang.Rustup"; Name = "Rust (rustup)" },
        @{ Id = "Oven-sh.Bun"; Name = "Bun" },
        @{ Id = "Kitware.CMake"; Name = "CMake" },
        @{ Id = "LLVM.LLVM"; Name = "LLVM (libclang, for whisper-rs bindings)" },
        # Pinned to the version the GitHub Actions build uses (build.yml).
        @{ Id = "KhronosGroup.VulkanSDK"; Name = "Vulkan SDK (GPU acceleration for Whisper)"; Version = "1.4.309.0" }
    )
    foreach ($p in $packages) {
        Step "Installing $($p.Name)"
        # Exit codes are ignored on purpose: "already installed" is non-zero.
        # Every tool is verified below instead.
        $pin = @()
        if ($p.Version) { $pin = @("--version", $p.Version) }
        winget install --id $p.Id --exact --silent --accept-package-agreements --accept-source-agreements @pin
    }
}

Update-SessionEnv

Step "Checking tools"
Require git "Install Git (winget install Git.Git)."
Require rustup "Install Rust (winget install Rustlang.Rustup)."
Require bun "Install Bun (winget install Oven-sh.Bun)."
Require cmake "Install CMake (winget install Kitware.CMake)."
rustup default stable-x86_64-pc-windows-msvc | Out-Null
Require cargo "Rust installed but cargo is missing; open a new terminal and run this again."

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vcTools = if (Test-Path $vswhere) {
    & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}
if (-not $vcTools) { Fail "Visual Studio C++ Build Tools not found. Re-run without -SkipInstall." }

$llvmBin = Join-Path $env:ProgramFiles "LLVM\bin"
if (-not (Test-Path (Join-Path $llvmBin "libclang.dll"))) { Fail "LLVM not found at $llvmBin (winget install LLVM.LLVM)." }
$env:LIBCLANG_PATH = $llvmBin

if (-not $env:VULKAN_SDK -or -not (Test-Path $env:VULKAN_SDK)) {
    Fail "VULKAN_SDK is not set. Install the Vulkan SDK (winget install KhronosGroup.VulkanSDK), then open a new terminal."
}
Write-Host "$(cargo --version) | bun $(bun --version) | Vulkan SDK $env:VULKAN_SDK"

git config --system core.longpaths true

# --- 2. Source -------------------------------------------------------------

# Use the checkout this script lives in, if it is one; otherwise clone.
$scriptRepo = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $scriptRepo "src-tauri\tauri.conf.json")) { $Dir = $scriptRepo }

if (Test-Path (Join-Path $Dir ".git")) {
    Step "Updating $Dir ($Branch)"
    git -C $Dir fetch origin
    git -C $Dir checkout $Branch
    git -C $Dir pull --ff-only origin $Branch
} else {
    Step "Cloning Typist into $Dir (private repo: sign in to GitHub when the browser opens)"
    git clone --branch $Branch $RepoUrl $Dir
}
if ($LASTEXITCODE -ne 0) { Fail "Could not get the source code." }
Set-Location $Dir

# --- 3. Build --------------------------------------------------------------

# winget installs CMake 4, which refuses whisper.cpp's old cmake_minimum_required
# (the same fix the macOS build needs).
$env:CMAKE_POLICY_VERSION_MINIMUM = "3.5"

# Short target directory: whisper-rs-sys's cmake paths overflow MAX_PATH otherwise.
$env:CARGO_TARGET_DIR = Join-Path $env:SystemDrive "\t"

if (-not $Native) {
    # Same as CI: no -march=native and nothing above SSE4.2, so the installer
    # runs on any x64 CPU (CPUs without AVX/FMA otherwise crash with an illegal
    # instruction). Vulkan does the heavy lifting, so the cost is small.
    foreach ($flag in "GGML_NATIVE", "GGML_AVX", "GGML_AVX2", "GGML_FMA", "GGML_F16C") {
        Set-Item "env:$flag" "OFF"
    }
}

Step "Installing frontend dependencies"
bun install
if ($LASTEXITCODE -ne 0) { Fail "bun install failed." }

Step "Building Typist (the first build takes 20-40 minutes; later builds are much faster)"
bun run tauri build
if ($LASTEXITCODE -ne 0) {
    # The MSI step (WiX) is the usual casualty, e.g. when Windows' optional
    # VBSCRIPT feature is turned off. The setup .exe doesn't need it.
    Write-Host "Full build failed; retrying with the setup .exe only..." -ForegroundColor Yellow
    bun run tauri build --bundles nsis
    if ($LASTEXITCODE -ne 0) { Fail "Build failed. The error is just above this line." }
}

# --- 4. Hand over ----------------------------------------------------------

$bundle = Join-Path $env:CARGO_TARGET_DIR "release\bundle"
$installers = @(Get-ChildItem -Path (Join-Path $bundle "nsis\*.exe"), (Join-Path $bundle "msi\*.msi") -ErrorAction SilentlyContinue)
if ($installers.Count -eq 0) { Fail "Build finished but no installer was found under $bundle." }

$out = Join-Path ([Environment]::GetFolderPath("Desktop")) "Typist-installers"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$installers | Copy-Item -Destination $out -Force

Step "Done"
$installers | ForEach-Object { Write-Host "  $out\$($_.Name)" -ForegroundColor Green }
Write-Host "Run the *-setup.exe to install Typist."
Invoke-Item $out
