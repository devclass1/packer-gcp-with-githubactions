# Packer template for Windows Server 2025 with IIS and OpenSSH on GCP
# Version: 1.0.0

packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.0.0"
    }
  }
}

# Variables
variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  description = "GCP Region"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "GCP Zone"
  default     = "us-central1-a"
}

variable "image_name" {
  type        = string
  description = "Name of the final image"
  default     = null
}

variable "ssh_password" {
  type        = string
  description = "Password for SSH user"
  sensitive   = true
  default     = null
}

variable "source_image_family" {
  type        = string
  description = "Source Windows Server image family"
  default     = "windows-2025"
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB"
  default     = 50
}

variable "machine_type" {
  type        = string
  description = "GCP machine type"
  default     = "n1-standard-4"
}

# Local variables
locals {
  timestamp     = formatdate("YYYYMMDDhhmmss", timestamp())
  image_name    = coalesce(var.image_name, "windows-2025-iis-${local.timestamp}")
  ssh_password  = coalesce(var.ssh_password, "PackerAdmin!2025")
}

# Source block
source "googlecompute" "windows-2025" {
  # GCP Configuration
  project_id              = var.project_id
  zone                    = var.zone
  source_image_project_id = ["windows-cloud"]
  source_image_family     = var.source_image_family
  
  # Instance Configuration
  disk_size               = var.disk_size
  machine_type            = var.machine_type
  tags                    = ["packer-builder", "windows-server", "ssh-access"]
  
  # Image Output Configuration
  image_name              = local.image_name
  image_family            = "windows-2025-iis"
  image_description       = "Windows Server 2025 with IIS and OpenSSH - Built on ${local.timestamp}"
  image_labels = {
    built_by    = "packer"
    built_on    = local.timestamp
    os          = "windows-2025"
    components  = "iis,openssh"
    source      = "github-actions"
  }
  
  # Network Configuration
  use_internal_ip         = false
  omit_external_ip        = false
  
  # SSH Communicator Configuration
  communicator            = "ssh"
  ssh_username            = "packer"
  ssh_password            = local.ssh_password
  ssh_timeout             = "45m"
  ssh_port                = 22
  ssh_handshake_attempts  = 100
  ssh_clear_authorized_keys = true
  
  # Windows-specific SSH settings
  ssh_file_transfer_method = "sftp"
  
  # Metadata
  metadata = {
    windows-startup-script-ps1 = file("${path.root}/scripts/setup-windows.ps1")
    ssh_password              = local.ssh_password
    serial-port-enable        = "true"
  }
  
  # Service Account
  service_account_email = ""
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]
}

# Build block
build {
  sources = ["source.googlecompute.windows-2025"]
  
  # Provisioners
  provisioner "powershell" {
    inline = [
      "Write-Host '=== PACKER BUILD STARTED ===' -ForegroundColor Cyan",
      "Write-Host 'Hostname: ' $env:COMPUTERNAME",
      "Write-Host 'Windows Version: ' (Get-WmiObject -Class Win32_OperatingSystem).Caption",
      "Write-Host 'Packer user: packer'",
      "Write-Host '=== BUILD CONFIGURATION VERIFIED ===' -ForegroundColor Green"
    ]
  }
  
  # Verify IIS installation
  provisioner "powershell" {
    inline = [
      "Write-Host 'Verifying IIS installation...'",
      "$iis = Get-WindowsFeature -Name Web-Server",
      "if ($iis.Installed) {",
      "  Write-Host '✅ IIS is installed' -ForegroundColor Green",
      "} else {",
      "  Write-Host '❌ IIS is not installed' -ForegroundColor Red",
      "  exit 1",
      "}"
    ]
  }
  
  # Verify SSH installation
  provisioner "powershell" {
    inline = [
      "Write-Host 'Verifying SSH installation...'",
      "$ssh = Get-Service -Name sshd -ErrorAction SilentlyContinue",
      "if ($ssh -and $ssh.Status -eq 'Running') {",
      "  Write-Host '✅ SSH is installed and running' -ForegroundColor Green",
      "} else {",
      "  Write-Host '❌ SSH is not running correctly' -ForegroundColor Red",
      "  exit 1",
      "}"
    ]
  }
  
  # Create test website
  provisioner "powershell" {
    inline = [
      "Write-Host 'Creating test website...'",
      "$websitePath = 'C:\\inetpub\\wwwroot'",
      "$indexContent = @'",
      "<!DOCTYPE html>",
      "<html>",
      "<head>",
      "  <title>Windows Server 2025 with IIS</title>",
      "  <style>",
      "    body { font-family: Arial, sans-serif; margin: 40px; background-color: #f0f0f0; }",
      "    .container { max-width: 800px; margin: auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }",
      "    h1 { color: #0078d4; }",
      "    .info { background: #f3f3f3; padding: 10px; border-radius: 5px; }",
      "  </style>",
      "</head>",
      "<body>",
      "  <div class='container'>",
      "    <h1>Windows Server 2025 with IIS</h1>",
      "    <p>This image was built with Packer on Google Cloud Platform.</p>",
      "    <div class='info'>",
      "      <p><strong>Build Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>",
      "      <p><strong>Image Name:</strong> ${local.image_name}</p>",
      "      <p><strong>Components:</strong> IIS, OpenSSH</p>",
      "    </div>",
      "  </div>",
      "</body>",
      "</html>",
      "'@",
      "Set-Content -Path \"$websitePath\\index.html\" -Value $indexContent -Force",
      "Write-Host '✅ Test website created' -ForegroundColor Green"
    ]
  }
  
  # Final cleanup
  provisioner "powershell" {
    inline = [
      "Write-Host 'Performing final cleanup...'",
      "# Clear event logs",
      "wevtutil el | ForEach-Object { wevtutil cl \"$_\" 2>$null }",
      "# Clear temp files",
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue",
      "Remove-Item -Path 'C:\\Users\\packer\\AppData\\Local\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue",
      "# Clear PowerShell history",
      "Remove-Item -Path (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue",
      "Write-Host '=== PACKER BUILD COMPLETED SUCCESSFULLY ===' -ForegroundColor Green"
    ]
  }
  
  # Post-processor to generate manifest
  post-processor "manifest" {
    output = "manifest.json"
    strip_path = true
    custom_data = {
      build_time   = local.timestamp
      image_name   = local.image_name
      project_id   = var.project_id
      source_image = var.source_image_family
    }
  }
}
