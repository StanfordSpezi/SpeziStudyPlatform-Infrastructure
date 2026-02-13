{
  local app(name, wave, config, envPath, envPrefix, ignoreDifferences=null) = {
    apiVersion: 'argoproj.io/v1alpha1',
    kind: 'Application',
    metadata: {
      name: envPrefix + '-' + name,
      namespace: 'argocd',
      annotations: {
        'argocd.argoproj.io/sync-wave': std.toString(wave),
      },
    },
    spec: {
      project: 'default',
      source: {
        repoURL: 'https://github.com/StanfordSpezi/spezi-study-platform-infrastructure.git',
        path: envPath,
        targetRevision: std.get(config, 'gitBranch', if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'main' else 'main'),
        plugin: {
          name: 'tanka',
          env: [
            {
              name: 'COMPONENT',
              value: name,
            },
            {
              name: 'ENVIRONMENT',
              value: if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'default' else 'local-dev',
            },
          ] + (if std.get(config, 'localIP', null) != null then [
            {
              name: 'LOCAL_IP',
              value: config.localIP,
            },
          ] else []),
        },
      },
      destination: {
        server: 'https://kubernetes.default.svc',
        namespace: config.namespace,
      },
      syncPolicy: {
        automated: {
          prune: true,
          selfHeal: true,
        },
        syncOptions: [
          'CreateNamespace=true',
          'ServerSideApply=true',
        ],
      },
    } + (if ignoreDifferences != null then { ignoreDifferences: ignoreDifferences } else {}),
  },
  withConfig(config)::
    local envPath = '.';
    local envPrefix = if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'prod' else 'local-dev';
    std.objectValues({
      // Wave 0
      'namespace-app': app('namespace', 0, config, envPath, envPrefix),
      'cnpg-crds-app': app('cloudnative-pg-crds', 0, config, envPath, envPrefix),
      'external-secrets-operator-app': {
        apiVersion: 'argoproj.io/v1alpha1',
        kind: 'Application',
        metadata: {
          name: envPrefix + '-external-secrets-operator',
          namespace: 'argocd',
          annotations: {
            'argocd.argoproj.io/sync-wave': '0',
          },
        },
        spec: {
          project: 'default',
          source: {
            repoURL: 'https://charts.external-secrets.io',
            chart: 'external-secrets',
            targetRevision: '0.19.2',
            helm: {
              parameters: [
                {
                  name: 'installCRDs',
                  value: 'true',
                },
              ],
            },
          },
          destination: {
            server: 'https://kubernetes.default.svc',
            namespace: 'external-secrets-system',
          },
          syncPolicy: {
            automated: {
              prune: true,
              selfHeal: true,
            },
            syncOptions: [
              'CreateNamespace=true',
              'ServerSideApply=true',
            ],
          },
        },
      },

      // Wave 1
      'traefik-app': app('traefik', 1, config, envPath, envPrefix),
      'cert-manager-app': app('cert-manager', 1, config, envPath, envPrefix),
      'external-secrets-app': app('external-secrets', 1, config, envPath, envPrefix),

      // Wave 2
      'cnpg-app': app('cloudnative-pg', 2, config, envPath, envPrefix),
      'auth-app': app('auth', 2, config, envPath, envPrefix),

      // Wave 3  
      'backend-app': app('backend', 3, config, envPath, envPrefix),
      'frontend-app': app('frontend', 3, config, envPath, envPrefix),
      'argocd-app': app('argocd', 3, config, envPath, envPrefix),
    }),
}
