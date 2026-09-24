# =============================================================================
#  install-windows.ps1 — set up WSL2 + Ubuntu so the suite can run on Windows
# -----------------------------------------------------------------------------
#  Frappe/ERPNext does not run natively on Windows. The supported way is
#  WSL2 (Windows Subsystem for Linux) running Ubuntu, which behaves exactly
#  like a Linux server — and then the bundle's ./install.sh works unchanged.
#
#  Run this in an **Administrator PowerShell**:
#     powershell -ExecutionPolicy Bypass -File .\windows\install-windows.ps1
#
#  Then REBOOT, open "Ubuntu" from the Start menu, and follow
#  windows/README.md (step 4) to clone + install the bundle.
# =============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[x] $msg" -ForegroundColor Red }

Write-Host ""
Write-Host "Jew_Pawn-Lending-Suite — Windows setup (WSL2 + Ubuntu)" -ForegroundColor Green
Write-Host ""

# --- 1. Windows version check (WSL2 needs Win10 2004+ / Win11) --------------
$os = Get-CimInstance Win32_OperatingSystem
$build = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
Write-Step "Windows: $($os.Caption) (build $build)"
if ($build -lt 19041) {
    Write-Err "WSL2 requires Windows 10 build 19041+ (2004) or Windows 11. Please update Windows."
    exit 1
}

# --- 2. Enable the Windows features WSL2 needs ------------------------------
Write-Step "Enabling 'Microsoft-Windows-Subsystem-Linux' and 'VirtualMachinePlatform'"
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

# --- 3. Install / update WSL and Ubuntu -------------------------------------
Write-Step "Installing WSL kernel + Ubuntu (this may take a few minutes)"
try {
    wsl.exe --install -d Ubuntu
} catch {
    Write-Warn "Automatic install failed. If this is an older Windows, install the WSL2 kernel update from:"
    Write-Warn "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
    Write-Warn "then run:  wsl --set-default-version 2  &&  wsl --install -d Ubuntu"
}

Write-Step "Setting WSL default version to 2"
try { wsl.exe --set-default-version 2 } catch { Write-Warn "Could not set default version yet." }

Write-Host ""
Write-Host "=============================================================================" -ForegroundColor Green
Write-Host " Next steps" -ForegroundColor Green
Write-Host "=============================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  1. REBOOT Windows (required for WSL2)."
Write-Host "  2. Open 'Ubuntu' from the Start menu; create your UNIX username/password."
Write-Host "  3. Inside Ubuntu run:"
Write-Host ""
Write-Host "       sudo apt update && sudo apt install -y git" -ForegroundColor White
Write-Host "       git clone https://github.com/ShyberDev/Jew_Pawn-Lending-Suite.git" -ForegroundColor White
Write-Host "       cd Jew_Pawn-Lending-Suite && ./install.sh" -ForegroundColor White
Write-Host ""
Write-Host "  4. Start it and open the desk from Windows:"
Write-Host ""
Write-Host "       sudo systemctl start mariadb && cd ~/frappe-bench && bench start" -ForegroundColor White
Write-Host "       # in your Windows browser:  http://localhost:8000/desk" -ForegroundColor White
Write-Host ""
Write-Host "  (WSL2 forwards localhost, so http://localhost:8000 works from Windows."
Write-Host "   For http://library.local:8000 add '127.0.0.1 library.local' to"
Write-Host "   C:\Windows\System32\drivers\etc\hosts as Administrator.)"
Write-Host ""
Write-Host "  Full details: windows/README.md" -ForegroundColor Cyan
Write-Host ""
