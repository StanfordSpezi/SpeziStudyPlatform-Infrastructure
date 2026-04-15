{
  local k = import 'k.libsonnet',
  withConfig(config)::
    {

      server_external_secret: {
        apiVersion: 'external-secrets.io/v1',
        kind: 'ExternalSecret',
        metadata: {
          name: 'spezistudyplatform-server-secret',
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
            name: 'spezistudyplatform-server-secret',
            creationPolicy: 'Owner',
          },
          data: [
            {
              secretKey: 'OAUTH_CLIENT_SECRET',
              remoteRef: {
                key: 'spezistudyplatform-server',
                property: 'OAUTH_CLIENT_SECRET',
                conversionStrategy: 'Default',
                decodingStrategy: 'None',
                metadataPolicy: 'None',
              },
            },
          ],
        },
      },

      server_config: k.core.v1.configMap.new('spezistudyplatform-server-config', {
        APP_ENVIRONMENT: if config.isProd then 'production' else 'development',
        KEYCLOAK_URL: 'http://keycloak.' + config.namespace + '.svc.cluster.local/auth',
        KEYCLOAK_REALM: 'spezistudyplatform',
        KEYCLOAK_CLIENT_ID: 'spezistudyplatform-server',
        KEYCLOAK_RESEARCHER_ROLE: 'spezistudyplatform-researcher',
        KEYCLOAK_PARTICIPANT_ROLE: 'spezistudyplatform-participant',
        DATABASE_HOST: 'spezistudyplatform-db-rw',
        DATABASE_NAME: 'spezistudyplatform',
      })
      + k.core.v1.configMap.metadata.withNamespace(config.namespace),

      server_deployment: k.apps.v1.deployment.new(
        name='spezistudyplatform-server',
        replicas=config.replicas.server,
        containers=[
          k.core.v1.container.new('spezistudyplatform-server-container', 'ghcr.io/stanfordspezi/spezistudyplatform-server:' + config.serverImageTag)
          + k.core.v1.container.withImagePullPolicy('Always')
          + k.core.v1.container.withPorts([k.core.v1.containerPort.new(8080)])
          + k.core.v1.container.resources.withRequests(config.resources.server.requests)
          + k.core.v1.container.resources.withLimits(config.resources.server.limits)
          + k.core.v1.container.securityContext.withAllowPrivilegeEscalation(false)
          + k.core.v1.container.securityContext.withRunAsNonRoot(true)
          + k.core.v1.container.securityContext.capabilities.withDrop(['ALL'])
          + k.core.v1.container.withEnvFrom([
            k.core.v1.envFromSource.configMapRef.withName('spezistudyplatform-server-config'),
          ])
          + k.core.v1.container.withEnv([
            k.core.v1.envVar.fromSecretRef('DATABASE_USERNAME', 'spezistudyplatform-postgres-credentials', 'username'),
            k.core.v1.envVar.fromSecretRef('DATABASE_PASSWORD', 'spezistudyplatform-postgres-credentials', 'password'),
            k.core.v1.envVar.fromSecretRef('KEYCLOAK_CLIENT_SECRET', 'spezistudyplatform-server-secret', 'OAUTH_CLIENT_SECRET'),
          ])
          + k.core.v1.container.readinessProbe.httpGet.withPath('/api/health')
          + k.core.v1.container.readinessProbe.httpGet.withPort(8080)
          + k.core.v1.container.readinessProbe.withInitialDelaySeconds(10)
          + k.core.v1.container.readinessProbe.withPeriodSeconds(10)
          + k.core.v1.container.livenessProbe.httpGet.withPath('/api/health')
          + k.core.v1.container.livenessProbe.httpGet.withPort(8080)
          + k.core.v1.container.livenessProbe.withInitialDelaySeconds(30)
          + k.core.v1.container.livenessProbe.withPeriodSeconds(15),
        ]
      )
      + k.apps.v1.deployment.spec.template.spec.withInitContainers([
        k.core.v1.container.new('spezistudyplatform-server-migrate', 'ghcr.io/stanfordspezi/spezistudyplatform-server:' + config.serverImageTag)
        + k.core.v1.container.withImagePullPolicy('Always')
        + k.core.v1.container.withCommand(['./SpeziStudyPlatformServer', 'migrate', '--yes'])
        + k.core.v1.container.securityContext.withAllowPrivilegeEscalation(false)
        + k.core.v1.container.securityContext.withRunAsNonRoot(true)
        + k.core.v1.container.securityContext.capabilities.withDrop(['ALL'])
        + k.core.v1.container.withEnvFrom([
          k.core.v1.envFromSource.configMapRef.withName('spezistudyplatform-server-config'),
        ])
        + k.core.v1.container.withEnv([
          k.core.v1.envVar.fromSecretRef('DATABASE_USERNAME', 'spezistudyplatform-postgres-credentials', 'username'),
          k.core.v1.envVar.fromSecretRef('DATABASE_PASSWORD', 'spezistudyplatform-postgres-credentials', 'password'),
        ]),
      ])
      + k.apps.v1.deployment.metadata.withNamespace(config.namespace)
      + k.apps.v1.deployment.metadata.withLabels({ app: 'spezistudyplatform-server' })
      + k.apps.v1.deployment.spec.selector.withMatchLabels({ app: 'spezistudyplatform-server' })
      + k.apps.v1.deployment.spec.template.metadata.withLabels({ app: 'spezistudyplatform-server' })
      + k.apps.v1.deployment.spec.strategy.withType(
        if config.isProd then 'RollingUpdate' else 'Recreate'
      )
      + (if config.isProd then
           k.apps.v1.deployment.spec.strategy.rollingUpdate.withMaxSurge('25%')
           + k.apps.v1.deployment.spec.strategy.rollingUpdate.withMaxUnavailable(0)
         else {}),

      server_service: k.core.v1.service.new(
        'spezistudyplatform-server-service',
        { app: 'spezistudyplatform-server' },
        [k.core.v1.servicePort.new(8080, 8080) + k.core.v1.servicePort.withName('http')]
      )
      + k.core.v1.service.metadata.withNamespace(config.namespace),
    }
}
