# =======================================================================================
# MANUAL ACTION REQUIRED (Production only)
# =======================================================================================
# The Google Cloud Terraform provider does not support creating OAuth 2.0 Client IDs
# for web applications directly. You must create these credentials manually and store
# them in Google Cloud Secret Manager (GCSM) before running the production setup.
#
# 1. Create the OAuth Client:
#    - Go to the GCP Console: https://console.cloud.google.com/
#    - Navigate to "APIs & Services" > "Credentials".
#    - Click "+ CREATE CREDENTIALS" > "OAuth client ID".
#    - Select "Web application" as the type.
#    - Add the following under "Authorized redirect URIs":
#      - For Production: https://platform.spezi.stanford.edu/auth/realms/spezistudyplatform/broker/google/endpoint
#      - For Local Dev: http://localhost:8081/auth/realms/spezistudyplatform/broker/google/endpoint
#    - Click "Create" and copy the "Client ID" and "Client Secret".
#
# 2. Store the Credentials in Secret Manager:
#    - Using the gcloud CLI or the GCP Console, create two secrets in this project
#      with the following exact names:
#
#      Secret Name: keycloak-google-sso-client-id
#      Secret Value: The Client ID you copied.
#
#      Secret Name: keycloak-google-sso-client-secret
#      Secret Value: The Client Secret you copied.
#
#    Example gcloud commands:
#    export PROJECT_ID="spezistudyplatform-dev" # Replace if different
#
#    echo -n "YOUR_CLIENT_ID" | gcloud secrets create keycloak-google-sso-client-id \
#      --project=$PROJECT_ID --data-file=-
#
#    echo -n "YOUR_CLIENT_SECRET" | gcloud secrets create keycloak-google-sso-client-secret \
#      --project=$PROJECT_ID --data-file=-
#
# The production setup script (spezi_setup.py prod) fetches these secrets via
# gcloud and passes them as variables to tofu automatically.
# =======================================================================================
