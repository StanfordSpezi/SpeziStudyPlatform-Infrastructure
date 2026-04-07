{
  local k = import 'k.libsonnet',
  withConfig(config)::
    {

      backend_external_secret: {
        apiVersion: 'external-secrets.io/v1',
        kind: 'ExternalSecret',
        metadata: {
          name: 'spezistudyplatform-backend-secret',
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
            name: 'spezistudyplatform-backend-secret',
            creationPolicy: 'Owner',
          },
          data: [
            {
              secretKey: 'OAUTH_CLIENT_SECRET',
              remoteRef: {
                key: 'spezistudyplatform-backend',
                property: 'OAUTH_CLIENT_SECRET',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
          ],
        },
      },

      backend_config: k.core.v1.configMap.new('spezistudyplatform-backend-config', {
        APP_ENVIRONMENT: if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'production' else 'development',
        KEYCLOAK_URL: 'http://keycloak.' + config.namespace + '.svc.cluster.local/auth',
        KEYCLOAK_REALM: 'spezistudyplatform',
        KEYCLOAK_CLIENT_ID: 'spezistudyplatform-server',
        KEYCLOAK_RESEARCHER_ROLE: 'spezistudyplatform-researcher',
        KEYCLOAK_PARTICIPANT_ROLE: 'spezistudyplatform-participant',
        DATABASE_HOST: 'spezistudyplatform-db-rw',
        DATABASE_NAME: 'spezistudyplatform',
      })
      + k.core.v1.configMap.metadata.withNamespace(config.namespace),

      backend_deployment: k.apps.v1.deployment.new(
        name='spezistudyplatform-backend',
        replicas=1,
        containers=[
          k.core.v1.container.new('spezistudyplatform-backend-container', 'ghcr.io/stanfordspezi/spezistudyplatform-server:' + config.backendImageTag)
          + k.core.v1.container.withImagePullPolicy('Always')
          + k.core.v1.container.withPorts([k.core.v1.containerPort.new(8080)])
          + k.core.v1.container.resources.withLimits({
            memory: '2Gi',
            cpu: '1',
          })
          + k.core.v1.container.withEnvFrom([
            k.core.v1.envFromSource.configMapRef.withName('spezistudyplatform-backend-config'),
          ])
          + k.core.v1.container.withEnv([
            k.core.v1.envVar.fromSecretRef('DATABASE_USERNAME', 'spezistudyplatform-postgres-credentials', 'username'),
            k.core.v1.envVar.fromSecretRef('DATABASE_PASSWORD', 'spezistudyplatform-postgres-credentials', 'password'),
            k.core.v1.envVar.fromSecretRef('KEYCLOAK_CLIENT_SECRET', 'spezistudyplatform-backend-secret', 'OAUTH_CLIENT_SECRET'),
          ]),
        ]
      )
      + k.apps.v1.deployment.metadata.withNamespace(config.namespace)
      + k.apps.v1.deployment.metadata.withLabels({ app: 'spezistudyplatform-backend' })
      + k.apps.v1.deployment.spec.selector.withMatchLabels({ app: 'spezistudyplatform-backend' })
      + k.apps.v1.deployment.spec.template.metadata.withLabels({ app: 'spezistudyplatform-backend' })
      + k.apps.v1.deployment.spec.strategy.withType('Recreate'),

      backend_service: k.core.v1.service.new(
        'spezistudyplatform-backend-service',
        { app: 'spezistudyplatform-backend' },
        [k.core.v1.servicePort.new(8080, 8080) + k.core.v1.servicePort.withName('http')]
      )
      + k.core.v1.service.metadata.withNamespace(config.namespace),
    }
}