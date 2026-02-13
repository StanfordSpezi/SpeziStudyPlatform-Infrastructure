# Known Issues

## Argo CD Keycloak login is currently broken

Logging into the Argo CD UI via Keycloak is not working right now. Until this is fixed, sign in with the built-in admin account instead of the Keycloak SSO flow.

**Investigate static IP teardown strategy**

During production teardown we currently rely on `tofu destroy -target=…` to avoid deleting the reserved static IP address. OpenTofu discourages routine `-target` use, so we should explore alternatives (separate state, `prevent_destroy`, or managing the IP outside OpenTofu) to better align with best practices.

**Workaround**
- Username: `admin`
- Password: run the same command printed by the setup script to grab the generated secret:

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  ```

Use the returned value as the password when the Argo CD login prompt appears.
