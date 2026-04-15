{
  withConfig(config)::
    if config.isProd then {
      // Default deny all ingress in the namespace
      'default-deny-ingress': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'default-deny-ingress',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {},
          policyTypes: ['Ingress'],
        },
      },

      // Allow Traefik to reach web and server pods
      'allow-traefik-to-apps': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-traefik-to-apps',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchExpressions: [{
              key: 'app',
              operator: 'In',
              values: [
                'spezistudyplatform-server',
                'spezistudyplatform-web',
              ],
            }],
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { 'app.kubernetes.io/name': 'traefik' },
              },
            }],
          }],
        },
      },

      // Allow Traefik to reach oauth2-proxy
      'allow-traefik-to-oauth2-proxy': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-traefik-to-oauth2-proxy',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchLabels: { app: 'oauth2-proxy' },
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { 'app.kubernetes.io/name': 'traefik' },
              },
            }],
            ports: [{ protocol: 'TCP', port: 4180 }],
          }],
        },
      },

      // Allow Traefik to reach Keycloak
      'allow-traefik-to-keycloak': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-traefik-to-keycloak',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchLabels: { 'app.kubernetes.io/name': 'keycloak' },
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { 'app.kubernetes.io/name': 'traefik' },
              },
            }],
            ports: [{ protocol: 'TCP', port: 8080 }],
          }],
        },
      },

      // Allow server to reach the database on port 5432
      'allow-server-to-db': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-server-to-db',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchLabels: { 'cnpg.io/cluster': 'spezistudyplatform-db' },
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { app: 'spezistudyplatform-server' },
              },
            }],
            ports: [{ protocol: 'TCP', port: 5432 }],
          }],
        },
      },

      // Allow Keycloak to reach the database on port 5432
      'allow-keycloak-to-db': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-keycloak-to-db',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchLabels: { 'cnpg.io/cluster': 'spezistudyplatform-db' },
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { 'app.kubernetes.io/name': 'keycloak' },
              },
            }],
            ports: [{ protocol: 'TCP', port: 5432 }],
          }],
        },
      },

      // Allow oauth2-proxy to reach Keycloak for OIDC
      'allow-oauth2-proxy-to-keycloak': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-oauth2-proxy-to-keycloak',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchLabels: { 'app.kubernetes.io/name': 'keycloak' },
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { app: 'oauth2-proxy' },
              },
            }],
            ports: [{ protocol: 'TCP', port: 8080 }],
          }],
        },
      },

      // Allow server to reach Keycloak for token validation
      'allow-server-to-keycloak': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-server-to-keycloak',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchLabels: { 'app.kubernetes.io/name': 'keycloak' },
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { app: 'spezistudyplatform-server' },
              },
            }],
            ports: [{ protocol: 'TCP', port: 8080 }],
          }],
        },
      },

      // Allow DNS egress for all pods
      'allow-dns-egress': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-dns-egress',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {},
          policyTypes: ['Egress'],
          egress: [{
            to: [{
              namespaceSelector: {
                matchLabels: { 'kubernetes.io/metadata.name': 'kube-system' },
              },
            }],
            ports: [
              { protocol: 'UDP', port: 53 },
              { protocol: 'TCP', port: 53 },
            ],
          }],
        },
      },

      // Allow CNPG pods to communicate with each other for replication
      'allow-cnpg-replication': {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'NetworkPolicy',
        metadata: {
          name: 'allow-cnpg-replication',
          namespace: config.namespace,
        },
        spec: {
          podSelector: {
            matchLabels: { 'cnpg.io/cluster': 'spezistudyplatform-db' },
          },
          policyTypes: ['Ingress'],
          ingress: [{
            from: [{
              podSelector: {
                matchLabels: { 'cnpg.io/cluster': 'spezistudyplatform-db' },
              },
            }],
            ports: [{ protocol: 'TCP', port: 5432 }],
          }],
        },
      },
    } else {},
}
