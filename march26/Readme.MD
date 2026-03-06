# Windows Server 2025 Image Builder with Packer and GitHub Actions

This repository automates the building of Windows Server 2025 custom images on Google Cloud Platform using Packer and GitHub Actions.

## Features

- ✅ Windows Server 2025 base image
- ✅ IIS web server installation
- ✅ OpenSSH Server for remote management
- ✅ Automated builds via GitHub Actions
- ✅ Monthly scheduled builds (security patches)
- ✅ Manual trigger option
- ✅ Image versioning with timestamps

## Prerequisites

1. **Google Cloud Platform Account**
   - Active GCP project
   - Billing enabled

2. **GitHub Repository**
   - Admin access to repository settings

## Setup Instructions

### 1. GCP Service Account Creation

```bash
# Enable required APIs
gcloud services enable compute.googleapis.com \
    cloudresourcemanager.googleapis.com \
    iam.googleapis.com

# Create service account
gcloud iam service-accounts create packer-builder \
    --display-name="Packer Builder"

# Grant permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:packer-builder@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:packer-builder@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"

# Download service account key
gcloud iam service-accounts keys create ~/gcp-key.json \
    --iam-account=packer-builder@YOUR_PROJECT_ID.iam.gserviceaccount.com

## GitHub Secrets Configuration

Add these secrets to your GitHub repository (**Settings → Secrets and variables → Actions**):

| Secret Name | Description |
|------------|-------------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `GCP_SERVICE_ACCOUNT_KEY` | Full JSON content of the service account key |
| `SSH_PASSWORD` | (Optional) Custom SSH password for packer user |

## Firewall Rules

Create the following firewall rules to allow Packer to communicate with the builder instance:

```bash
# Allow SSH access for Packer communication
gcloud compute firewall-rules create allow-packer-ssh \
    --allow tcp:22 \
    --source-ranges 0.0.0.0/0 \
    --target-tags packer-builder

# Allow WinRM access for Packer communication (fallback method)
gcloud compute firewall-rules create allow-packer-winrm \
    --allow tcp:5985-5986 \
    --source-ranges 0.0.0.0/0 \
    --target-tags packer-builder
