{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local kustomize = tanka.kustomize.new(std.thisFile),
  withConfig(config)::
    local cnpgManifests = kustomize.build('../../kustomize/cloudnative-pg/');
    // Convert to array if it's an object, otherwise use as is
    local manifestArray = if std.isArray(cnpgManifests) then cnpgManifests else std.objectValues(cnpgManifests);
    local filtered = [
      resource
      for resource in manifestArray
      if resource.kind != 'CustomResourceDefinition'
    ];
    local allManifests = filtered + [
      {
        apiVersion: 'postgresql.cnpg.io/v1',
        kind: 'Cluster',
        metadata: {
          name: 'spezistudyplatform-db',
          namespace: config.namespace,
        },
        spec: {
          imageName: 'ghcr.io/cloudnative-pg/postgresql:17-bullseye',
          instances: 1,
          storage: {
            size: '1Gi',
          },
          monitoring: {
            enablePodMonitor: true,
          },
          enableSuperuserAccess: true,
          bootstrap: {
            initdb: {
              database: 'spezistudyplatform',
              owner: 'spezistudyplatform',
              secret: {
                name: 'spezistudyplatform-postgres-credentials',
              },
            },
          },
        },
      },
      {
        apiVersion: 'external-secrets.io/v1',
        kind: 'ExternalSecret',
        metadata: {
          name: 'spezistudyplatform-postgres-credentials',
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
            name: 'spezistudyplatform-postgres-credentials',
            creationPolicy: 'Owner',
            template: {
              type: 'kubernetes.io/basic-auth',
              engineVersion: 'v2',
              data: {
                username: '{{ .username }}',
                password: '{{ .password }}',
              },
            },
          },
          data: [
            {
              secretKey: 'username',
              remoteRef: {
                key: 'spezistudyplatform-postgres-credentials',
                property: 'username',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
            {
              secretKey: 'password',
              remoteRef: {
                key: 'spezistudyplatform-postgres-credentials',
                property: 'password',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
          ],
        },
      },
    ];
    {
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in allManifests
      if std.objectHas(resource, 'kind')
    },
}