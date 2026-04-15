{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    {
      // ExternalSecret for Keycloak admin password
      keycloak_admin_secret: {
        apiVersion: 'external-secrets.io/v1',
        kind: 'ExternalSecret',
        metadata: {
          name: 'keycloak-admin-secret',
          namespace: config.namespace,
          annotations: {
            'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          },
        },
        spec: {
          refreshInterval: '15s',
          secretStoreRef: { name: 'vault-backend', kind: 'ClusterSecretStore' },
          target: { name: 'keycloak-admin-secret', creationPolicy: 'Owner' },
          data: [{
            secretKey: 'admin-password',
            remoteRef: {
              key: 'keycloak-admin',
              property: 'admin-password',
              conversionStrategy: 'Default',
              decodingStrategy: 'None',
              metadataPolicy: 'None',
            },
          }],
        },
      },

      // ExternalSecret for Keycloak external database credentials
      keycloak_db_secret: {
        apiVersion: 'external-secrets.io/v1',
        kind: 'ExternalSecret',
        metadata: {
          name: 'keycloak-db-secret',
          namespace: config.namespace,
          annotations: {
            'argocd.argoproj.io/compare-options': 'IgnoreExtraneous',
          },
        },
        spec: {
          refreshInterval: '15s',
          secretStoreRef: { name: 'vault-backend', kind: 'ClusterSecretStore' },
          target: { name: 'keycloak-db-secret', creationPolicy: 'Owner' },
          data: [
            {
              secretKey: 'username',
              remoteRef: {
                key: 'keycloak-db-credentials',
                property: 'username',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
            {
              secretKey: 'password',
              remoteRef: {
                key: 'keycloak-db-credentials',
                property: 'password',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
          ],
        },
      },

      keycloak: helm.template('keycloak', '../../charts/keycloak', {
        namespace: config.namespace,
        version: '25.1.1',
        values: {
          global+: {
            security+: {
              allowInsecureImages: true,
            },
          },
          image+: {
            registry: 'docker.io',
            repository: 'bitnamilegacy/keycloak',
          },
          extraEnvVars: [
            {
              name: 'KC_HTTP_RELATIVE_PATH',
              value: '/auth',
            },
            {
              name: 'KC_HOSTNAME',
              value: 'https://' + config.domain + '/auth',
            },
          ] + (
            if config.isProd then [
              {
                name: 'KC_PROXY_HEADERS',
                value: 'xforwarded',
              },
              {
                name: 'KC_PROXY',
                value: 'edge',
              },
              {
                name: 'KC_HOSTNAME_STRICT',
                value: 'false',
              },
            ] else [
              {
                name: 'KC_HOSTNAME_STRICT',
                value: 'true',
              },
            ]
          ),
          customReadinessProbe: {
            failureThreshold: 3,
            httpGet: {
              path: '/auth/realms/master',
              port: 8080,
            },
            initialDelaySeconds: 120,
            timeoutSeconds: 5,
          },
          resources: {
            limits: {
              cpu: '1000m',
              memory: '2048Mi',
            },
            requests: {
              cpu: '500m',
              memory: '1024Mi',
            },
          },
          tolerations: [
            {
              key: 'node-role.kubernetes.io/control-plane',
              operator: 'Exists',
              effect: 'NoSchedule',
            },
          ],
          auth: {
            existingSecret: 'keycloak-admin-secret',
            passwordSecretKey: 'admin-password',
          },
          postgresql: {
            enabled: false,
          },
          externalDatabase: {
            host: 'spezistudyplatform-db-rw',
            port: 5432,
            database: 'keycloak',
            existingSecret: 'keycloak-db-secret',
            existingSecretUserKey: 'username',
            existingSecretPasswordKey: 'password',
          },
        },
      }),
    },
}
