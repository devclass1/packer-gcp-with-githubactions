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
