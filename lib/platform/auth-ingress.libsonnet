{
  withConfig(config)::
    {
      // Headers middleware to ensure proper forwarded headers for Keycloak
      'keycloak-headers-middleware': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'keycloak-headers',
          namespace: config.namespace,
        },
        spec: {
          headers: {
            customRequestHeaders: {
              'X-Forwarded-Proto': 'https',
              'X-Forwarded-Port': '443',
            },
          },
        },
      },
      'keycloak-ingress': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: 'keycloak-ingress',
          namespace: config.namespace,
          annotations: {
            'ingress.kubernetes.io/ssl-redirect': 'true',
            'cert-manager.io/cluster-issuer': if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'letsencrypt-prod' else 'selfsigned-issuer',
            'ingress.kubernetes.io/proxy-buffer-size': '128k',
          },
        },
        spec: {
          entryPoints: [
            'websecure',
          ],
          routes: [
            {
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/oauth2`)',
              priority: 99,
              kind: 'Rule',
              services: [
                {
                  name: 'oauth2-proxy',
                  port: 80,
                },
              ],
              middlewares: [],
            },
            {
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/auth`)',
              priority: 99,
              kind: 'Rule',
              services: [
                {
                  name: 'keycloak',
                  port: 80,
                },
              ],
              middlewares: [
                { name: 'keycloak-headers' },
              ],
            },
          ],
          tls: {
            secretName: config.namespace + '-main-tls-secret',
          },
        },
      },
    },
}