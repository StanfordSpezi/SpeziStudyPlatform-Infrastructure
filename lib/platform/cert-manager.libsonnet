{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local kustomize = tanka.kustomize.new(std.thisFile),
  withConfig(config)::
    local certManagerManifests = kustomize.build('../../kustomize/cert-manager/');
    // Convert to array if it's an object, otherwise use as is
    local manifestArray = if std.isArray(certManagerManifests) then certManagerManifests else std.objectValues(certManagerManifests);
    local processedManifests = [
      if resource.kind == 'Deployment' && resource.metadata.name == 'cert-manager' then
        resource + {
          spec+: {
            template+: {
              spec+: {
                containers: [
                  if container.name == 'cert-manager' then
                    container + {
                      args: container.args + ['--leader-election-namespace=cert-manager'],
                    }
                  else container
                  for container in resource.spec.template.spec.containers
                ],
              },
            },
          },
        }
      else resource
      for resource in manifestArray
    ];
    {
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in processedManifests
    } + (
      if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then {
        // Production: Let's Encrypt ClusterIssuer
        'letsencrypt-prod-clusterissuer': {
          apiVersion: 'cert-manager.io/v1',
          kind: 'ClusterIssuer',
          metadata: {
            name: 'letsencrypt-prod',
          },
          spec: {
            acme: {
              server: 'https://acme-v02.api.letsencrypt.org/directory',
              email: 'spam@muci.sh',
              privateKeySecretRef: {
                name: 'letsencrypt-prod',
              },
              solvers: [
                {
                  http01: {
                    ingress: {
                      class: 'traefik',
                    },
                  },
                },
              ],
            },
          },
        },
        
        // Production TLS Certificate
        'main-tls-certificate': {
          apiVersion: 'cert-manager.io/v1',
          kind: 'Certificate',
          metadata: {
            name: config.namespace + '-main-tls-cert',
            namespace: config.namespace,
          },
          spec: {
            commonName: config.domain,
            secretName: config.namespace + '-main-tls-secret',
            issuerRef: {
              name: 'letsencrypt-prod',
              kind: 'ClusterIssuer',
            },
            dnsNames: [
              config.domain,
            ],
          },
        },
      } else {
        // Local Dev: Self-signed ClusterIssuer
        'selfsigned-clusterissuer': {
          apiVersion: 'cert-manager.io/v1',
          kind: 'ClusterIssuer',
          metadata: {
            name: 'selfsigned-issuer',
          },
          spec: {
            selfSigned: {},
          },
        },
        
        // Local Dev TLS Certificate
        'main-tls-certificate': {
          apiVersion: 'cert-manager.io/v1',
          kind: 'Certificate',
          metadata: {
            name: config.namespace + '-main-tls-cert',
            namespace: config.namespace,
          },
          spec: {
            commonName: config.domain,
            secretName: config.namespace + '-main-tls-secret',
            issuerRef: {
              name: 'selfsigned-issuer',
              kind: 'ClusterIssuer',
            },
            dnsNames: [
              config.domain,
              'spezi.127.0.0.1.nip.io',
            ],
          },
        },
      }
    ),
}