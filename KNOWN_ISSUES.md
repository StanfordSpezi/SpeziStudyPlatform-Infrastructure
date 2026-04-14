# Known Issues

## Argo CD Keycloak login is currently broken

Logging into the Argo CD UI via Keycloak is not working right now. Until this is fixed, sign in with the built-in admin account instead of the Keycloak SSO flow.

**Workaround**
- Username: `admin`
- Password: run the same command printed by the setup script to grab the generated secret:

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  ```

Use the returned value as the password when the Argo CD login prompt appears.
