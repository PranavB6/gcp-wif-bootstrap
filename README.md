# GCP - GitHub Actions Workload Identity Federation Setup

The `gcp-gh-actions-wif-setup.sh` script sets up the required resources in Google Cloud Platform (GCP) for GitHub Actions to impersonate a service account using Workload Identity Federation (WIF).

The script performs the following actions:

1. Assigns roles to the authenticated user
2. Enables the Identity and Access Management (IAM) API
3. Creates a service account
4. Assign roles to the service account
5. Creates a Workload Identity Pool
6. Creates a Workload Identity Provider
7. Allows authentications from Workload Identity Provider to impersonate the service account

Note: The script will only configure the impersonation for the created service account for the specified GitHub repositories.

## How to use

Run the gcp-gh-actions-wif-setup.sh script in a GCP Cloud Shell
