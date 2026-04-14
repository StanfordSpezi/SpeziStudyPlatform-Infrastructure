{
  withConfig(config)::
    if config.externalSecrets.enabled then {
        // HashiCorp Vault for development
        vault: {
          apiVersion: 'v1',
          kind: 'Namespace',
          metadata: {
            name: 'vault',
          },
        },
        
        'vault-server': {
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          metadata: {
            name: 'vault',
            namespace: 'vault',
            labels: {
              app: 'vault',
            },
          },
          spec: {
            replicas: 1,
            selector: {
              matchLabels: {
                app: 'vault',
              },
            },
            template: {
              metadata: {
                labels: {
                  app: 'vault',
                },
              },
              spec: {
                containers: [
                  {
                    name: 'vault',
                    image: 'hashicorp/vault:1.15',
                    args: [
                      'vault',
                      'server',
                      '-dev',
                      '-dev-root-token-id=' + config.externalSecrets.vault.rootToken,
                      '-dev-listen-address=0.0.0.0:8200',
                    ],
                    ports: [
                      {
                        containerPort: 8200,
                        name: 'vault',
                      },
                    ],
                    env: [
                      {
                        name: 'VAULT_DEV_ROOT_TOKEN_ID',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                    resources: {
                      limits: {
                        memory: '256Mi',
                        cpu: '250m',
                      },
                      requests: {
                        memory: '64Mi',
                        cpu: '50m',
                      },
                    },
                  },
                ],
              },
            },
          },
        },
        
        'vault-service': {
          apiVersion: 'v1',
          kind: 'Service',
          metadata: {
            name: 'vault',
            namespace: 'vault',
          },
          spec: {
            selector: {
              app: 'vault',
            },
            ports: [
              {
                port: 8200,
                targetPort: 8200,
                name: 'vault',
              },
            ],
          },
        },

        // Test secret in Vault (this would normally be done via vault CLI)
        'vault-server-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-server-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && (vault kv get secret/spezistudyplatform-server >/dev/null 2>&1 || vault kv put secret/spezistudyplatform-server OAUTH_CLIENT_SECRET=change-me-in-production) || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        'vault-web-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-web-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && (vault kv get secret/spezistudyplatform-web >/dev/null 2>&1 || vault kv put secret/spezistudyplatform-web OAUTH_CLIENT_SECRET=dummy-web-secret) || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        'vault-db-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-db-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && (vault kv get secret/spezistudyplatform-postgres-credentials >/dev/null 2>&1 || vault kv put secret/spezistudyplatform-postgres-credentials username=spezistudyplatform password=spezistudyplatform1!2@) || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        'vault-oauth2-proxy-secret-setup': {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: 'vault-oauth2-proxy-secret-setup',
            namespace: 'vault',
          },
          spec: {
            template: {
              spec: {
                restartPolicy: 'Never',
                containers: [
                  {
                    name: 'vault-setup',
                    image: 'hashicorp/vault:1.15',
                    command: [
                      'sh',
                      '-c',
                      'sleep 10 && (vault kv get secret/oauth2-proxy-secret >/dev/null 2>&1 || vault kv put secret/oauth2-proxy-secret client-id=oauth2-proxy client-secret=c4h7rptpKNYyHOpuH780CXEGyLvYmo6A cookie-secret=local-dev-cookie-secret-32-chars) || true',
                    ],
                    env: [
                      {
                        name: 'VAULT_ADDR',
                        value: config.externalSecrets.vault.server,
                      },
                      {
                        name: 'VAULT_TOKEN',
                        value: config.externalSecrets.vault.rootToken,
                      },
                    ],
                  },
                ],
              },
            },
          },
        },

        // ClusterSecretStore for Vault
        'vault-secret-store': {
          apiVersion: 'external-secrets.io/v1',
          kind: 'ClusterSecretStore',
          metadata: {
            name: 'vault-backend',
          },
          spec: {
            provider: {
              vault: {
                server: config.externalSecrets.vault.server,
                path: 'secret',
                version: 'v2',
                auth: {
                  tokenSecretRef: {
                    name: 'vault-token',
                    namespace: 'external-secrets-system',
                    key: 'token',
                  },
                },
              },
            },
          },
        },

        // Token secret for Vault authentication
        'vault-token-secret': {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: 'vault-token',
            namespace: 'external-secrets-system',
          },
          type: 'Opaque',
          data: {
            token: std.base64(config.externalSecrets.vault.rootToken),
          },
        },

        
    } else {}
}
