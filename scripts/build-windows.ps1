<#
.SYNOPSIS
    Builds the Typist Windows installers on this PC (64-bit Windows, x64),
    or prepares this PC so a Mac can run that build remotely over SSH.

.DESCRIPTION
    Local build (default), run once per machine and again for each fresh build:
      1. installs the build tools with winget (skipped if already present),
      2. clones (or updates) the Typist repository,
      3. builds the .exe (NSIS) and .msi installers,
      4. copies them to Desktop\Typist-installers and opens that folder.

    -EnableRemote (run once, at the PC): installs the build tools, then turns on
    Windows' OpenSSH server for the home network only, with key login for the
    one Mac key given by -PublicKey and password logins switched off. After that
    the Mac runs scripts/remote-windows-build.sh and nothing is needed here.

    The build mirrors the GitHub Actions Windows build (.github/workflows/build.yml):
    long paths on, a short target directory for whisper-rs-sys, the Vulkan SDK,
    and the same CPU-compatibility flags, so the result matches that build.

    Installing the tools accepts their licence agreements through winget
    (Visual Studio Build Tools, Rust, Bun, Git, CMake, LLVM, Vulkan SDK).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build-windows.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build-windows.ps1 -EnableRemote -PublicKey "ssh-ed25519 AAAA... mac"

.PARAMETER Dir
    Where the repository lives (cloned there if missing). Default: %USERPROFILE%\Typist.
.PARAMETER Branch
    Branch to build. Default: typist-main.
.PARAMETER OutDir
    Where the finished installers are copied. Default: Desktop\Typist-installers.
.PARAMETER SkipInstall
    Skip the tool installation step (tools already installed).
.PARAMETER Native
    Optimise for THIS PC's CPU (faster Whisper) instead of building a portable
    installer. Don't share a Native build: it can crash on older CPUs.
.PARAMETER NoFetch
    Build the existing checkout as it is, without updating it (the Mac's
    remote build syncs the checkout itself before running this).
.PARAMETER EnableRemote
    Install the tools and set up SSH for remote builds instead of building now.
.PARAMETER PublicKey
    The Mac's SSH public key (one line) that -EnableRemote authorises.
#>
param(
    [string]$Dir = (Join-Path $env:USERPROFILE "Typist"),
    [string]$Branch = "typist-main",
    [string]$OutDir = (Join-Path ([Environment]::GetFolderPath("Desktop")) "Typist-installers"),
    [switch]$SkipInstall,
    [switch]$Native,
    [switch]$NoFetch,
    [switch]$EnableRemote,
    [string]$PublicKey = ""
)

$ErrorActionPreference = "Stop"
$RepoUrl = "https://github.com/Joaoha/Typist.git"
$OverSsh = [bool]$env:SSH_CONNECTION

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

# Native tools (git, cargo, bun) write progress to stderr. Windows PowerShell
# 5.1 turns that into error records whenever its own output is redirected, as
# in an SSH session, and "Stop" then aborts on the first progress line. cmd
# merges stderr into stdout first, so only the exit code decides.
function Invoke-Native([string]$commandLine) {
    cmd /c "$commandLine 2>&1"
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
if ($EnableRemote -and $PublicKey -notmatch '^ssh-(ed25519|rsa) \S+') {
    Fail "-EnableRemote needs the Mac's public key: -PublicKey `"ssh-ed25519 AAAA...`"."
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($OverSsh) {
        # No way to answer an elevation prompt remotely. An administrator
        # account logging in with a key gets full rights automatically.
        Fail "This SSH session is not elevated. Log in with an administrator account."
    }
    # Long paths, Visual Studio Build Tools and the SSH server need administrator rights.
    Write-Host "Restarting as administrator (Windows will ask for permission)..."
    # -NoExit keeps the new window open so the result (or error) stays readable.
    $forward = @("-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"",
        "-Dir", "`"$Dir`"", "-Branch", $Branch, "-OutDir", "`"$OutDir`"")
    if ($SkipInstall) { $forward += "-SkipInstall" }
    if ($Native) { $forward += "-Native" }
    if ($EnableRemote) { $forward += @("-EnableRemote", "-PublicKey", "`"$PublicKey`"") }
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
Invoke-Native "rustup default stable-x86_64-pc-windows-msvc" | Out-Null
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

Invoke-Native "git config --system core.longpaths true"

# --- Remote setup (-EnableRemote) ------------------------------------------

if ($EnableRemote) {
    Step "Installing the OpenSSH server (Windows feature)"
    $capability = Get-WindowsCapability -Online -Name "OpenSSH.Server*" | Select-Object -First 1
    if ($capability.State -ne "Installed") { Add-WindowsCapability -Online -Name $capability.Name | Out-Null }
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd   # the first start writes C:\ProgramData\ssh\sshd_config

    Step "Allowing SSH from this home network only"
    $ruleName = "OpenSSH-Server-In-TCP"
    if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH Server (sshd)" -Direction Inbound `
            -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
    }
    Set-NetFirewallRule -Name $ruleName -Enabled True -Profile Any -RemoteAddress LocalSubnet

    Step "Authorising the Mac's key; switching password logins off"
    # Administrators' keys live in one machine-wide file, which sshd only
    # trusts when only Administrators and SYSTEM can touch it (SIDs, so this
    # works in any Windows language).
    $keys = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    $known = (Test-Path $keys) -and (Select-String -Path $keys -SimpleMatch $PublicKey.Trim() -Quiet)
    if (-not $known) { Add-Content -Path $keys -Value $PublicKey.Trim() -Encoding ascii }
    icacls $keys /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null

    # sshd uses the first value it reads, so a line at the top wins over the
    # commented defaults and the Match block further down.
    $config = Join-Path $env:ProgramData "ssh\sshd_config"
    $lines = Get-Content $config
    if ($lines -notcontains "PasswordAuthentication no") {
        Set-Content -Path $config -Value (@("PasswordAuthentication no") + $lines) -Encoding ascii
    }
    Restart-Service sshd

    Step "Remote builds are set up"
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual -ErrorAction SilentlyContinue |
        Select-Object -First 1).IPAddress
    Write-Host "Tell Claude this line:" -ForegroundColor Green
    Write-Host "  Windows user: $env:USERNAME   PC: $env:COMPUTERNAME   address: $ip" -ForegroundColor Green
    Write-Host "Keep the PC plugged in and awake when you ask for a build."
    exit 0
}

# --- 2. Source -------------------------------------------------------------

# Use the checkout this script lives in, if it is one; otherwise clone.
$scriptRepo = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $scriptRepo "src-tauri\tauri.conf.json")) { $Dir = $scriptRepo }

if ($NoFetch) {
    if (-not (Test-Path (Join-Path $Dir ".git"))) { Fail "-NoFetch, but there is no checkout at $Dir." }
    Step "Building $Dir as it is (-NoFetch)"
    $global:LASTEXITCODE = 0
} elseif (Test-Path (Join-Path $Dir ".git")) {
    Step "Updating $Dir ($Branch)"
    Invoke-Native "git -C `"$Dir`" fetch origin"
    if ($LASTEXITCODE -eq 0) { Invoke-Native "git -C `"$Dir`" checkout $Branch" }
    if ($LASTEXITCODE -eq 0) { Invoke-Native "git -C `"$Dir`" pull --ff-only origin $Branch" }
} else {
    Step "Cloning Typist into $Dir (private repo: sign in to GitHub when the browser opens)"
    Invoke-Native "git clone --branch $Branch $RepoUrl `"$Dir`""
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

# Keep the PC from sleeping until this script exits (a remote build has no
# keyboard activity to hold it awake). ES_CONTINUOUS | ES_SYSTEM_REQUIRED.
Add-Type -Namespace TypistBuild -Name Power -MemberDefinition `
    '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
[TypistBuild.Power]::SetThreadExecutionState([uint32]2147483649) | Out-Null  # 0x80000001

Step "Installing frontend dependencies"
Invoke-Native "bun install"
if ($LASTEXITCODE -ne 0) { Fail "bun install failed." }

Step "Building Typist (the first build takes 20-40 minutes; later builds are much faster)"
Invoke-Native "bun run tauri build"
if ($LASTEXITCODE -ne 0) {
    # The MSI step (WiX) is the usual casualty, e.g. when Windows' optional
    # VBSCRIPT feature is turned off. The setup .exe doesn't need it.
    Write-Host "Full build failed; retrying with the setup .exe only..." -ForegroundColor Yellow
    Invoke-Native "bun run tauri build --bundles nsis"
    if ($LASTEXITCODE -ne 0) { Fail "Build failed. The error is just above this line." }
}

# --- 4. Hand over ----------------------------------------------------------

$bundle = Join-Path $env:CARGO_TARGET_DIR "release\bundle"
$installers = @(Get-ChildItem -Path (Join-Path $bundle "nsis\*.exe"), (Join-Path $bundle "msi\*.msi") -ErrorAction SilentlyContinue)
if ($installers.Count -eq 0) { Fail "Build finished but no installer was found under $bundle." }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# Only this build's installers: an older version's files would look current.
Get-ChildItem -Path $OutDir -Filter "Typist_*" -ErrorAction SilentlyContinue | Remove-Item -Force
$installers | Copy-Item -Destination $OutDir -Force

Step "Done"
$installers | ForEach-Object { Write-Host "  $OutDir\$($_.Name)" -ForegroundColor Green }
if (-not $OverSsh) {
    Write-Host "Run the *-setup.exe to install Typist."
    Invoke-Item $OutDir
}
exit 0
