# Windows Server 2025 Setup Script for Packer
# This script runs during instance creation to prepare the Windows image

<#
.SYNOPSIS
    Configures Windows Server 2025 for Packer image building
.DESCRIPTION
    This script sets up WinRM, creates the packer user, installs OpenSSH,
    installs IIS, and performs system optimization
.NOTES
    Version: 1.0.0
    Author: Packer Builder
#>

# Enable strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Logging function
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Color coding based on level
    switch ($Level) {
        'INFO'    { Write-Host $logMessage -ForegroundColor Cyan }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Write to serial console for GCP logging
    try {
        Add-Content -Path "\\.\COM1" -Value $logMessage -ErrorAction SilentlyContinue
    }
    catch {
        # Serial console might not be available, ignore
    }
}

# Function to wait for network connectivity
function Wait-ForNetwork {
    Write-Log "Waiting for network connectivity..." -Level INFO
    $timeout = 300 # 5 minutes
    $interval = 10
    $elapsed = 0
    
    while ($elapsed -lt $timeout) {
        if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet) {
            Write-Log "Network is available" -Level SUCCESS
            return $true
        }
        Write-Log "Waiting for network... ($elapsed seconds elapsed)" -Level INFO
        Start-Sleep -Seconds $interval
        $elapsed += $interval
    }
    
    Write-Log "Network timeout after $timeout seconds" -Level WARNING
    return $false
}

# Function to set Windows features
function Set-WindowsFeatures {
    Write-Log "Configuring Windows features..." -Level INFO
    
    # Set network profile to Private
    Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
    Write-Log "Network profile set to Private" -Level SUCCESS
    
    # Disable Windows Defender (for build performance)
    if (Get-Command -Name Set-MpPreference -ErrorAction SilentlyContinue) {
        Set-MpPreference -DisableRealtimeMonitoring $true
        Write-Log "Windows Defender real-time monitoring disabled" -Level INFO
    }
    
    # Enable Remote Desktop
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    Write-Log "Remote Desktop enabled" -Level SUCCESS
}

# Function to create packer user
function New-PackerUser {
    param(
        [string]$Username = "packer",
        [string]$Password
    )
    
    Write-Log "Creating packer user..." -Level INFO
    
    try {
        # Check if user exists
        $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
        if (-not $user) {
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            New-LocalUser -Name $Username -Password $securePassword -FullName "Packer User" -Description "Packer automation user" -PasswordNeverExpires
            Add-LocalGroupMember -Group "Administrators" -Member $Username
            Add-LocalGroupMember -Group "Remote Desktop Users" -Member $Username -ErrorAction SilentlyContinue
            Write-Log "User '$Username' created and added to Administrators" -Level SUCCESS
        } else {
            Write-Log "User '$Username' already exists" -Level INFO
        }
    }
    catch {
        Write-Log "Failed to create user: $_" -Level ERROR
        throw
    }
}

# Function to configure WinRM
function Set-WinRMConfiguration {
    Write-Log "Configuring WinRM..." -Level INFO
    
    try {
        # Configure WinRM
        winrm quickconfig -quiet -force
        
        # Allow unencrypted traffic (for Packer communication)
        winrm set winrm/config/service '@{AllowUnencrypted="true"}'
        winrm set winrm/config/service/auth '@{Basic="true"}'
        
        # Increase timeout and max envelope size
        winrm set winrm/config '@{MaxTimeoutms="1800000"}'
        winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="1000"}'
        
        # Configure firewall
        New-NetFirewallRule -DisplayName "WinRM HTTP" -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
        New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
        
        # Restart WinRM
        Restart-Service -Name WinRM
        
        Write-Log "WinRM configured successfully" -Level SUCCESS
    }
    catch {
        Write-Log "WinRM configuration failed: $_" -Level WARNING
    }
}

# Function to install OpenSSH
function Install-OpenSSH {
    Write-Log "Installing OpenSSH Server..." -Level INFO
    
    $sshInstalled = $false
    
    # Method 1: Using Add-WindowsCapability
    try {
        Write-Log "Method 1: Using Add-WindowsCapability..." -Level INFO
        $capability = Get-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction SilentlyContinue
        
        if ($capability -and $capability.State -ne "Installed") {
            $result = Add-WindowsCapability -Online -Name "OpenSSH.Server~~~~0.0.1.0" -ErrorAction Stop
            if ($result.State -eq "Installed") {
                Write-Log "OpenSSH installed via Add-WindowsCapability" -Level SUCCESS
                $sshInstalled = $true
            }
        } elseif ($capability.State -eq "Installed") {
            Write-Log "OpenSSH already installed" -Level INFO
            $sshInstalled = $true
        }
    }
    catch {
        Write-Log "Method 1 failed: $_" -Level WARNING
    }
    
    # Method 2: Using DISM
    if (-not $sshInstalled) {
        try {
            Write-Log "Method 2: Using DISM..." -Level INFO
            $feature = Get-WindowsOptionalFeature -Online -FeatureName "OpenSSH.Server" -ErrorAction SilentlyContinue
            
            if ($feature -and $feature.State -ne "Enabled") {
                Enable-WindowsOptionalFeature -Online -FeatureName "OpenSSH.Server" -All -NoRestart -ErrorAction Stop
                Write-Log "OpenSSH installed via DISM" -Level SUCCESS
                $sshInstalled = $true
            } elseif ($feature.State -eq "Enabled") {
                Write-Log "OpenSSH already enabled" -Level INFO
                $sshInstalled = $true
            }
        }
        catch {
            Write-Log "Method 2 failed: $_" -Level WARNING
        }
    }
    
    # Method 3: Manual download from GitHub
    if (-not $sshInstalled) {
        try {
            Write-Log "Method 3: Manual download from GitHub..." -Level INFO
            $sshUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip"
            $zipPath = "$env:TEMP\OpenSSH.zip"
            $extractPath = "$env:ProgramFiles\OpenSSH"
            
            Invoke-WebRequest -Uri $sshUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            
            # Install SSH
            & "$extractPath\install-sshd.ps1"
            
            Write-Log "OpenSSH manually installed" -Level SUCCESS
            $sshInstalled = $true
        }
        catch {
            Write-Log "Method 3 failed: $_" -Level ERROR
        }
    }
    
    return $sshInstalled
}

# Function to configure OpenSSH
function Set-OpenSSHConfiguration {
    Write-Log "Configuring OpenSSH..." -Level INFO
    
    try {
        # Configure SSH to allow password authentication
        $sshDir = "$env:ProgramData\ssh"
        if (-not (Test-Path $sshDir)) {
            New-Item -ItemType Directory -Path $sshDir -Force
        }
        
        $sshdConfig = @"
# OpenSSH Server Configuration
# Generated by Packer on $(Get-Date)

# Network
Port 22
ListenAddress 0.0.0.0
Protocol 2

# Host Keys
HostKey $sshDir\ssh_host_rsa_key
HostKey $sshDir\ssh_host_dsa_key
HostKey $sshDir\ssh_host_ecdsa_key
HostKey $sshDir\ssh_host_ed25519_key

# Authentication
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
AuthenticationMethods password,publickey

# Users
AllowUsers packer Administrator
PermitRootLogin no

# Session
MaxAuthTries 3
MaxSessions 10

# Logging
SyslogFacility AUTH
LogLevel INFO

# Subsystem
Subsystem sftp sftp-server.exe
"@
        
        Set-Content -Path "$sshDir\sshd_config" -Value $sshdConfig -Force
        
        # Set service startup type
        Set-Service -Name sshd -StartupType Automatic
        Set-Service -Name ssh-agent -StartupType Automatic
        
        # Configure firewall
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue
        
        # Start services
        Start-Service sshd
        Start-Service ssh-agent
        
        Write-Log "OpenSSH configured successfully" -Level SUCCESS
    }
    catch {
        Write-Log "OpenSSH configuration failed: $_" -Level WARNING
    }
}

# Function to install IIS
function Install-IIS {
    Write-Log "Installing IIS and Web Server role..." -Level INFO
    
    try {
        $features = @(
            'Web-Server',
            'Web-WebSockets',
            'Web-Asp-Net45',
            'Web-Mgmt-Console',
            'Web-Mgmt-Tools',
            'Web-Scripting-Tools',
            'Web-Windows-Auth',
            'Web-Basic-Auth'
        )
        
        Install-WindowsFeature -Name $features -IncludeManagementTools -ErrorAction Stop
        
        # Start default website
        Start-Service -Name W3SVC
        Set-Service -Name W3SVC -StartupType Automatic
        
        Write-Log "IIS installed successfully" -Level SUCCESS
    }
    catch {
        Write-Log "IIS installation failed: $_" -Level ERROR
        throw
    }
}

# Function to optimize Windows
function Optimize-Windows {
    Write-Log "Optimizing Windows for image reuse..." -Level INFO
    
    # Disable hibernation
    powercfg -h off
    Write-Log "Hibernation disabled" -Level INFO
    
    # Set power scheme to High Performance
    powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    Write-Log "Power scheme set to High Performance" -Level INFO
    
    # Disable Windows Update automatic download
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Write-Log "Automatic Windows Update disabled" -Level INFO
    
    # Clean up temporary files
    Write-Log "Cleaning temporary files..." -Level INFO
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Clear event logs
    wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
}

# Main execution
function Main {
    Write-Log "=== WINDOWS SERVER 2025 SETUP STARTED ===" -Level SUCCESS
    Write-Log "Hostname: $env:COMPUTERNAME" -Level INFO
    
    # Wait for network
    Wait-ForNetwork
    
    # Configure Windows
    Set-WindowsFeatures
    
    # Create packer user
    $sshPassword = if ($env:ssh_password) { $env:ssh_password } else { "PackerAdmin!2025" }
    New-PackerUser -Username "packer" -Password $sshPassword
    
    # Configure WinRM
    Set-WinRMConfiguration
    
    # Install and configure OpenSSH
    $sshInstalled = Install-OpenSSH
    if ($sshInstalled) {
        Set-OpenSSHConfiguration
    }
    
    # Install IIS
    Install-IIS
    
    # Optimize Windows
    Optimize-Windows
    
    Write-Log "=== WINDOWS SERVER 2025 SETUP COMPLETED SUCCESSFULLY ===" -Level SUCCESS
}

# Run main function
Main
