function(staticIP=null, vaultServer=null, vaultToken=null) {
  // Base configuration that can be customized per environment
  base:: {
    namespace: 'spezistudyplatform',
    domain: null,  // Must be set by environment
    tlsSecretName: 'tls-secret',
    storageClass: null,  // Must be set by environment
    loadBalancerIP: null,  // Optional, set by environment if needed
    mode: 'PRODUCTION',  // Default to production mode
    caCrt: null,  // Must be set by environment
    webImageTag: 'latest',  // Override per environment or deployment
    serverImageTag: 'latest',  // Override per environment or deployment

    // Convenience booleans derived from mode
    isDev:: self.mode == 'DEV',
    isProd:: self.mode == 'PRODUCTION',

    // Scaling and resource sizing
    replicas: { server: 1, web: 1, db: 1 },
    dbStorageSize: '1Gi',
    traefikLogLevel: 'INFO',

    // Per-environment resource sizing
    resources: {
      server: {
        requests: { memory: '256Mi', cpu: '100m' },
        limits: { memory: '512Mi', cpu: '500m' },
      },
      web: {
        requests: { memory: '64Mi', cpu: '25m' },
        limits: { memory: '256Mi', cpu: '100m' },
      },
    },

    // External Secrets configuration (disabled by default)
    externalSecrets: {
      enabled: false,
      provider: 'vault',
      vault: {
        server: 'http://vault.vault.svc.cluster.local:8200',
        rootToken: 'dev-only-token',  // Only for development
      },
    },

    // Validation
    assert self.domain != null : 'domain must be set in environment config',
    assert self.storageClass != null : 'storageClass must be set in environment config',
  },

  // Production configuration
  prod:: self.base {
    domain: 'platform.spezi.stanford.edu',
    loadBalancerIP: staticIP,
    storageClass: 'standard-rw',
    mode: 'PRODUCTION',
    caCrt: null,
    webImageTag: 'v0.1.0',
    serverImageTag: 'v0.1.0',
    replicas: { server: 2, web: 2, db: 3 },
    dbStorageSize: '50Gi',
    traefikLogLevel: 'WARN',
    resources+: {
      server+: {
        requests: { memory: '512Mi', cpu: '250m' },
        limits: { memory: '2Gi', cpu: '1' },
      },
      web+: {
        requests: { memory: '128Mi', cpu: '50m' },
        limits: { memory: '1Gi', cpu: '100m' },
      },
    },
    externalSecrets+: {
      enabled: true,
      vault+: {
        server: if vaultServer != null then vaultServer else error 'vaultServer must be provided for production',
        rootToken: if vaultToken != null then vaultToken else error 'vaultToken must be provided for production',
      },
    },
    assert self.webImageTag != 'latest' : 'Pin image tags in production (webImageTag)',
    assert self.serverImageTag != 'latest' : 'Pin image tags in production (serverImageTag)',
    assert self.externalSecrets.vault.rootToken != 'dev-only-token' : 'Do not use dev-only-token in production',
  },

  // Production bootstrap: only generates ArgoCD Application manifests,
  // so vault/image-tag values are not rendered into workloads.
  prodBootstrap:: self.base {
    domain: 'platform.spezi.stanford.edu',
    loadBalancerIP: staticIP,
    storageClass: 'standard-rw',
    mode: 'PRODUCTION',
    caCrt: null,
    webImageTag: 'bootstrap',
    serverImageTag: 'bootstrap',
    replicas: { server: 2, web: 2, db: 3 },
    dbStorageSize: '50Gi',
    traefikLogLevel: 'WARN',
    externalSecrets+: {
      enabled: true,
      vault+: {
        server: 'https://vault.example.com:8200',
        rootToken: 'bootstrap-placeholder',
      },
    },
  },

  // Local development configuration
  localDev(ip=staticIP):: self.base {
    domain: 'spezi.' + ip + '.nip.io',
    loadBalancerIP: ip,
    storageClass: 'standard',
    mode: 'DEV',
    webImageTag: 'pr-123',
    serverImageTag: 'pr-17',
    traefikLogLevel: 'DEBUG',
    externalSecrets+: {
      enabled: true,
      provider: 'vault',
    },
  },
}
