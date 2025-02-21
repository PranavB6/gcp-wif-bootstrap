#!/bin/bash

# ============================================================
# Configuration
# ------------------------------------------------------------

# ----- Bash -----
# Exit the script if any command fails
set -e

# ----- Project -----
PROJECT_ID=""
AUTHENTICATED_USER_EMAIL=$(gcloud auth list --filter=status:ACTIVE --format='value(account)')
ROLES_FOR_AUTHENTICATED_USER=()

# ----- Service Account -----
SERVICE_ACCOUNT_NAME="github-actions-sa"
SERVICE_ACCOUNT_DISPLAY_NAME="GitHub Actions SA"
SERVICE_ACCOUNT_DESCRIPTION="Service account used by GitHub actions to manage resources"
SERVICE_ACCOUNT_ROLES=()
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# ----- Workload Identity Federation -----
WIF_POOL_NAME="github-actions-pool"
WIF_POOL_DISPLAY_NAME="GitHub Actions Pool"
WIF_POOL_DESCRIPTION="Workload Identity Pool for GitHub Actions"

# Only OIDC provider is supported
WIF_PROVIDER_NAME="github-actions-provider"
WIF_PROVIDER_DISPLAY_NAME="GitHub Actions Provider"
WIF_PROVIDER_DESCRIPTION="Workload Identity Provider for GitHub Actions"
WIF_PROVIDER_ISSUER_URI="https://token.actions.githubusercontent.com"
WIF_PROVIDER_ATTRIBUTE_MAPPING=(
    "google.subject=assertion.sub"
    "attribute.actor=assertion.actor"
    "attribute.aud=assertion.aud"
    "attribute.repository=assertion.repository"
    "attribute.repository_owner=assertion.repository_owner"
)
# Attribute Condition Example for multiple owners: "attribute.repository_owner == '<Owner1>' || attribute.repository_owner == '<Owner2>/')"
WIF_PROVIDER_ATTRIBUTE_CONDITION=""

# ----- GitHub Actions -----

# List of GitHub repositories authorized to impersonate the service account
# Format: "<owner>/<repository>"
GITHUB_REPOSITORIES_AUTHORIZED_FOR_IMPERSONATION=()

# ============================================================

# +--------------------------------------------------+
# |                   Variables                      |
# +--------------------------------------------------+

# Roles required to enable Google Cloud APIs
REQUIRED_ROLES_FOR_AUTHENTICATED_USER=("roles/iam.serviceAccountAdmin" "roles/serviceusage.serviceUsageAdmin")

declare -A COLORS
COLORS=(
    ["RED"]='\033[31m'
    ["BLUE"]='\033[34m'
    ["GREEN"]='\033[32m'
    ["GRAY"]='\033[90m'
    ["RESET"]='\033[0m'
)

# +--------------------------------------------------+
# |               Helper Functions                   |
# +--------------------------------------------------+

echo_success() {
    local message="$1"
    echo -e "${COLORS[GREEN]}[SUCCESS] ${message}${RESET}"
}

echo_info() {
    local message="$1"
    echo -e "${COLORS[BLUE]}[INFO] ${message}${RESET}"
}

trace_command() {
    local func="$1"
    local args=("${@:2}")

    echo -e -n "${COLORS[GRAY]}"

    (
        set -x
        "$func" "${args[@]}"
    )

    echo -e -n "${COLORS[RESET]}"
}

# ============================================================
# Setup gcloud CLI
# ------------------------------------------------------------

trace_command gcloud config set project "${PROJECT_ID}"
echo_success "Project set to ${PROJECT_ID}"

# Retrieve the GCP project number
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
echo_success "Retrieved Project Number: ${PROJECT_NUMBER}"

MERGED_ROLES=("${REQUIRED_ROLES_FOR_AUTHENTICATED_USER[@]}" "${ROLES_FOR_AUTHENTICATED_USER[@]}")

# Assign roles to authenticated user
for role in "${MERGED_ROLES[@]}"; do
    trace_command gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="user:${AUTHENTICATED_USER_EMAIL}" \
        --role="${role}" \
        --condition=None
    echo_success "Assigned role '${role}' to '${AUTHENTICATED_USER_EMAIL}'"
done

# ============================================================
# Enable Google Cloud APIs
# ------------------------------------------------------------

trace_command gcloud services enable iam.googleapis.com
echo_success "Enabled Identity and Access Management (IAM) API"

# ============================================================
# Create Service Account
# ------------------------------------------------------------

# Check if the service account already exists
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" &>/dev/null; then
    echo_info "Service Account '${SERVICE_ACCOUNT_NAME}' already exists"
else
    # Create the service account if it does not exist
    trace_command gcloud iam service-accounts create ${SERVICE_ACCOUNT_NAME} \
        --description="${SERVICE_ACCOUNT_DESCRIPTION}" \
        --display-name="${SERVICE_ACCOUNT_DISPLAY_NAME}"
    echo_success "Created Service Account '${SERVICE_ACCOUNT_NAME}'"
fi

# Assign roles to the service account
for role in "${SERVICE_ACCOUNT_ROLES[@]}"; do
    trace_command gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
        --role="${role}" \
        --condition=None
    echo_success "Assigned role '${role}' to '${SERVICE_ACCOUNT_EMAIL}'"
done

# ============================================================
# Setup Workload Identity Federation
# ------------------------------------------------------------

# Create Workload Identity Pool
trace_command gcloud iam workload-identity-pools create ${WIF_POOL_NAME} \
    --project="${PROJECT_ID}" \
    --location="global" \
    --display-name="${WIF_POOL_DISPLAY_NAME}" \
    --description="${WIF_POOL_DESCRIPTION}"
echo_success "Created Workload Identity Pool '${WIF_POOL_NAME}'"

# Concat attribute mappings into a comma separated string
ATTRIBUTE_MAPPING=$(IFS=','; echo "${WIF_PROVIDER_ATTRIBUTE_MAPPING[*]}")

# Create Workload Identity Provider
trace_command gcloud iam workload-identity-pools providers create-oidc ${WIF_PROVIDER_NAME} \
    --project="${PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WIF_POOL_NAME}" \
    --display-name="${WIF_PROVIDER_DISPLAY_NAME}" \
    --description="${WIF_PROVIDER_DESCRIPTION}" \
    --issuer-uri="${WIF_PROVIDER_ISSUER_URI}" \
    --attribute-mapping="${ATTRIBUTE_MAPPING}" \
    --attribute-condition="${WIF_PROVIDER_ATTRIBUTE_CONDITION}"
echo_success "Created Workload Identity Provider '${WIF_PROVIDER_NAME}'"

# Allow authentications from Workload Identity Provider to impersonate the service account
for github_repository in "${GITHUB_REPOSITORIES_AUTHORIZED_FOR_IMPERSONATION[@]}"; do
    trace_command gcloud iam service-accounts add-iam-policy-binding ${SERVICE_ACCOUNT_EMAIL} \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_NAME}/attribute.repository/${github_repository}"
    echo_success "Allowed Workload Identity Provider to impersonate '${SERVICE_ACCOUNT_EMAIL}' for '${github_repository}'"
done
