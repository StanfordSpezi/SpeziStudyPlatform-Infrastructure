function(staticIP=null) {
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
    replicas: { server: 1, web: 1 },
    dbStorageSize: '1Gi',
    traefikLogLevel: 'INFO',

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
    storageClass: null,  // Must be overridden for production deployments
    mode: 'PRODUCTION',
    caCrt: null,
    replicas: { server: 2, web: 2 },
    dbStorageSize: '50Gi',
    traefikLogLevel: 'WARN',
    externalSecrets+: {
      enabled: true,
      vault+: {
        // Production must override these to point to a real Vault instance.
        // The assertions below prevent the dev-only defaults from being used.
        server: null,
        rootToken: null,
      },
    },
    assert self.webImageTag != 'latest' : 'Pin image tags in production (webImageTag)',
    assert self.serverImageTag != 'latest' : 'Pin image tags in production (serverImageTag)',
    assert self.externalSecrets.vault.server != null : 'externalSecrets.vault.server must be set for production',
    assert self.externalSecrets.vault.rootToken != 'dev-only-token' : 'Do not use dev-only-token in production',
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
