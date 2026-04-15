{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    {
      traefik: helm.template('traefik', '../../charts/traefik', {
        namespace: config.namespace,
        values: {
          service: {
            enabled: true,
            type: if config.isDev then 'NodePort' else 'LoadBalancer',
            spec: if config.isDev then {} else {
              loadBalancerIP: config.loadBalancerIP,
            },
          },
          logs: {
            general: {
              level: config.traefikLogLevel,
            },
            access: {
              enabled: true,
              fields: {
                headers: {
                  defaultmode: 'keep',
                },
              },
            },
          },
          persistence: {
            enabled: true,
            name: 'traefik-data',
            accessMode: 'ReadWriteOnce',
            size: '1Gi',
            storageClass: config.storageClass,
            path: '/data',
            annotations: {},
          },
          deployment: {
            hostNetwork: config.isDev,
            dnsPolicy: if config.isDev then 'ClusterFirstWithHostNet' else null,
            initContainers: [
              {
                name: 'volume-permissions',
                image: 'traefik:v2.10.4',
                command: [
                  'sh',
                  '-c',
                  'touch /data/acme.json; chown 65532:65532 /data/acme.json; chmod -v 600 /data/acme.json',
                ],
                securityContext: {
                  runAsNonRoot: false,
                  runAsGroup: 0,
                  runAsUser: 0,
                },
                volumeMounts: [
                  {
                    name: 'traefik-data',
                    mountPath: '/data',
                    readOnly: false,
                  },
                ],
              },
            ],
          },
          podSecurityContext: {
            fsGroupChangePolicy: 'OnRootMismatch',
            runAsGroup: 65532,
            runAsNonRoot: true,
            runAsUser: 65532,
          },
          ports: if config.isDev then {
            web: {
              port: 80,
              nodePort: 30080,
              expose: {
                default: true,
              },
            },
            websecure: {
              port: 443,
              nodePort: 30443,
              expose: {
                default: true,
              },
              tls: {
                enabled: true,
              },
            },
          } else {},
          ingressRoute: {
            dashboard: {
              enabled: true,
            },
          },
          additionalArguments: if config.isDev then [
            '--entrypoints.websecure.forwardedHeaders.trustedIPs=10.244.0.0/16,127.0.0.1/32,172.16.0.0/12',
            '--entrypoints.web.forwardedHeaders.trustedIPs=10.244.0.0/16,127.0.0.1/32,172.16.0.0/12',
          ] else [],
        },
      }),
      
      // HTTP-to-HTTPS redirect middleware
      'redirect-https-middleware': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'redirect-https',
          namespace: config.namespace,
        },
        spec: {
          redirectScheme: {
            scheme: 'https',
            permanent: true,
          },
        },
      },

      // Security headers middleware (HSTS, anti-clickjacking, anti-sniffing)
      'security-headers-middleware': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'security-headers',
          namespace: config.namespace,
        },
        spec: {
          headers: {
            stsSeconds: 31536000,
            stsIncludeSubdomains: true,
            stsPreload: true,
            forceSTSHeader: true,
            frameDeny: true,
            contentTypeNosniff: true,
            browserXssFilter: true,
            referrerPolicy: 'strict-origin-when-cross-origin',
          },
        },
      },

      // HTTP catch-all IngressRoute that redirects to HTTPS
      'http-redirect-ingress': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: 'http-redirect',
          namespace: config.namespace,
        },
        spec: {
          entryPoints: ['web'],
          routes: [{
            match: 'HostRegexp(`.+`)',
            kind: 'Rule',
            priority: 1,
            middlewares: [{ name: 'redirect-https' }],
            services: [{
              name: config.namespace + '-web-service',
              port: 80,
            }],
          }],
        },
      },

      // OAuth2 Proxy Middleware for forward authentication
      'oauth2-proxy-middleware': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'oauth2-proxy',
          namespace: config.namespace,
        },
        spec: {
          forwardAuth: {
            address: 'http://oauth2-proxy.' + config.namespace + '.svc.cluster.local/oauth2/auth_or_start',
            trustForwardHeader: true,
            authResponseHeaders: [
              'X-Auth-Request-User',
              'X-Auth-Request-Email',
              'X-Auth-Request-Groups',
              'X-Auth-Request-Access-Token',
            ],
            authRequestHeaders: [],
          },
        },
      },

      // OAuth2 Error Handling Middleware
      'oauth2-errors-middleware': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'oauth2-errors',
          namespace: config.namespace,
        },
        spec: {
          errors: {
            status: [
              '401-403',
            ],
            service: {
              name: 'oauth2-proxy',
              port: 80,
            },
            query: '/oauth2/sign_in?rd={url}',
          },
        },
      },

      // Main application IngressRoute with OAuth2 protection
      'main-application-ingress': {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: config.namespace + '-ingress',
          namespace: config.namespace,
          annotations: {
            'cert-manager.io/cluster-issuer': if config.isProd then 'letsencrypt-prod' else 'selfsigned-issuer',
            'ingress.kubernetes.io/proxy-buffer-size': '128k',
            'ingress.kubernetes.io/auth-response-headers': 'X-Auth-Request-User, X-Auth-Request-Email, X-Auth-Request-Groups',
          },
        },
        spec: {
          entryPoints: ['websecure'],
          routes: [
            {
              // Catch-all for the web SPA. The keycloak IngressRoute
              // (Host && PathPrefix(`/auth`|`/oauth2`)) and the `/api` rule
              // below are more specific and win on their own paths; this
              // route then serves /, /env.js, /favicon.ico, /assets/*, and
              // any other top-level static file the SPA references.
              match: 'Host(`' + config.domain + '`)',
              priority: 1,
              kind: 'Rule',
              services: [
                {
                  name: config.namespace + '-web-service',
                  port: 80,
                },
              ],
              middlewares: [
                { name: 'security-headers' },
                { name: 'oauth2-proxy' },
                { name: 'oauth2-errors' },
              ],
            },
            {
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/api`)',
              priority: 2,
              kind: 'Rule',
              services: [
                {
                  name: config.namespace + '-server-service',
                  port: 8080,
                },
              ],
              middlewares: [
                { name: 'security-headers' },
                { name: 'oauth2-proxy' },
                { name: 'oauth2-errors' },
              ],
            },
          ],
          tls: {
            secretName: config.namespace + '-main-tls-secret',
          },
        },
      },

    } + (
      // Traefik Dashboard: only exposed in dev (no auth middleware)
      if config.isDev then {
        'traefik-dashboard-ingress': {
          apiVersion: 'traefik.io/v1alpha1',
          kind: 'IngressRoute',
          metadata: {
            name: 'dashboard',
            namespace: config.namespace,
            annotations: {
              'traefik.ingress.kubernetes.io/router.tls': 'true',
            },
          },
          spec: {
            entryPoints: ['web'],
            routes: [{
              match: "PathPrefix('/dashboard')",
              kind: 'Rule',
              services: [{ name: 'api@internal' }],
            }],
          },
        },
      } else {}
    ),
}
