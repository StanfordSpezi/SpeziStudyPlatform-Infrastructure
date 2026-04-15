{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    local secretObject = {
      apiVersion: 'external-secrets.io/v1',
      kind: 'ExternalSecret',
      metadata: {
        name: 'oauth2-proxy-secret',
        namespace: config.namespace,
        annotations: {
          'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
        },
      },
      spec: {
        refreshInterval: '15s',
        secretStoreRef: {
          name: 'vault-backend',
          kind: 'ClusterSecretStore',
        },
        target: {
          name: 'oauth2-proxy-secret',
          creationPolicy: 'Owner',
        },
        data: [
          {
            secretKey: 'client-id',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'client-id',
              conversionStrategy: 'Default',
              decodingStrategy: 'None',
              metadataPolicy: 'None',
            },
          },
          {
            secretKey: 'client-secret',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'client-secret',
              conversionStrategy: 'Default',
              decodingStrategy: 'None',
              metadataPolicy: 'None',
            },
          },
          {
            secretKey: 'cookie-secret',
            remoteRef: {
              key: 'oauth2-proxy-secret',
              property: 'cookie-secret',
              conversionStrategy: 'Default',
              decodingStrategy: 'None',
              metadataPolicy: 'None',
            },
          },
        ],
      },
    };
    {
      oauth2_proxy_secret: secretObject,
      oauth2_proxy_error_template: {
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: {
          name: 'oauth2-proxy-error-template',
          namespace: config.namespace,
        },
        data: {
          'error.html': |||
            <!DOCTYPE html>
            <html lang="en">
              <head>
                <meta charset="utf-8" />
                <title>Access Requires Approval</title>
                <style>
                  body {
                    margin: 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                    background: #f6f7fb;
                    color: #1b1f23;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    min-height: 100vh;
                  }
                  .card {
                    background: #fff;
                    padding: 2.5rem;
                    max-width: 520px;
                    box-shadow: 0 12px 32px rgba(15, 23, 42, 0.12);
                    border-radius: 16px;
                    text-align: center;
                  }
                  h1 {
                    font-size: 1.75rem;
                    margin-bottom: 0.75rem;
                  }
                  p {
                    margin-top: 0.5rem;
                    line-height: 1.5;
                    color: #374151;
                  }
                  .status {
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    padding: 0.35rem 0.85rem;
                    font-weight: 600;
                    border-radius: 999px;
                    background: #fef3c7;
                    color: #92400e;
                    margin-bottom: 1rem;
                  }
                  a {
                    color: #1d4ed8;
                    text-decoration: none;
                    font-weight: 600;
                  }
                  a:hover {
                    text-decoration: underline;
                  }
                </style>
              </head>
              <body>
                <main class="card">
                  <div class="status">{{ .StatusCode }} {{ .Title }}</div>
                  <h1>Access Pending Approval</h1>
                  <p>
                    Thanks for signing in, but your account doesn't have access to the
                    Spezi Study Platform yet.
                  </p>
                  <p>
                    Please reach out to the platform administrator to request access. If
                    this is unexpected, close this window and try signing in again.
                  </p>
                </main>
              </body>
            </html>
          |||,
        },
      },
    } + (
      if config.isProd then {
        'oauth2-proxy-ca-secret': {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: 'oauth2-proxy-ca-secret',
            namespace: config.namespace,
          },
          type: 'Opaque',
          stringData: {
            'ca.crt': config.caCrt,
          },
        },
      } else {}
    ) + {
      oauth2_proxy: helm.template('oauth2-proxy', '../../charts/oauth2-proxy', {
        namespace: config.namespace,
        values: {
          global+: {
            security+: {
              allowInsecureImages: true,
            },
          },
          image+: {
            registry: 'docker.io',
            repository: 'bitnamilegacy/oauth2-proxy',
          },
          configuration: {
            content: (
              if config.isDev then |||
                provider = "keycloak-oidc"
                oidc_issuer_url = "http://keycloak.%(namespace)s.svc.cluster.local/auth/realms/spezistudyplatform"
                skip_oidc_discovery = true
                login_url = "https://%(domain)s/auth/realms/spezistudyplatform/protocol/openid-connect/auth"
                redeem_url = "http://keycloak.%(namespace)s.svc.cluster.local/auth/realms/spezistudyplatform/protocol/openid-connect/token"
                oidc_jwks_url = "http://keycloak.%(namespace)s.svc.cluster.local/auth/realms/spezistudyplatform/protocol/openid-connect/certs"
                profile_url = "http://keycloak.%(namespace)s.svc.cluster.local/auth/realms/spezistudyplatform/protocol/openid-connect/userinfo"
                validate_url = "http://keycloak.%(namespace)s.svc.cluster.local/auth/realms/spezistudyplatform/protocol/openid-connect/userinfo"
                email_domains = ["*"]
                upstreams = ["static://200"]
                scope = "openid profile email groups"
                redirect_url = "https://%(domain)s/oauth2/callback"
                cookie_domains = ["%(domain)s"]
              ||| % { domain: config.domain, namespace: config.namespace } else |||
                provider = "keycloak-oidc"
                oidc_issuer_url = "https://%(domain)s/auth/realms/spezistudyplatform"
                email_domains = ["*"]
                upstreams = ["static://200"]
                scope = "openid profile email groups"
                redirect_url = "https://%(domain)s/oauth2/callback"
                cookie_domains = ["%(domain)s"]
              ||| % { domain: config.domain, namespace: config.namespace }
            ),
            existingSecret: 'oauth2-proxy-secret',
          },
          ingress: {
            enabled: false,
          },
          extraArgs: [
            '--skip-provider-button=true',
            '--whitelist-domain=*.' + config.domain,
            '--allowed-role=spezistudyplatform-authorized-users',
            '--pass-access-token=true',
            '--cookie-csrf-expire=60m',
            '--pass-authorization-header=true',
            '--set-xauthrequest=true',
            '--code-challenge-method=S256',
            '--reverse-proxy=true',
            '--custom-templates-dir=/templates',
            '--standard-logging=true',
          ] + (
            if config.isDev then
              ['--insecure-oidc-skip-issuer-verification=true']
            else
              []
          ),
          extraVolumes: [
            {
              name: 'oauth2-proxy-templates',
              configMap: {
                name: 'oauth2-proxy-error-template',
              },
            },
          ],
          extraVolumeMounts: [
            {
              name: 'oauth2-proxy-templates',
              mountPath: '/templates',
              readOnly: true,
            },
          ],
          redis: {
            enabled: false,
          },
          sessionStorage: {
            type: 'cookie',
          },
          extraEnv: [
            {
              name: 'OAUTH2_PROXY_REVERSE_PROXY',
              value: 'true',
            },
          ],
        },
      }),
    }
}
