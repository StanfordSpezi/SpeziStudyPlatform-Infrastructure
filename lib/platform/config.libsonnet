function(staticIP='34.168.138.135') {
  // Base configuration that can be customized per environment
  base:: {
    namespace: 'spezistudyplatform',
    domain: null, // Must be set by environment
    tlsSecretName: 'tls-secret',
    storageClass: null, // Must be set by environment
    loadBalancerIP: null, // Optional, set by environment if needed
    mode: 'PRODUCTION', // Default to production mode
    caCrt: null, // Must be set by environment
    frontendImageTag: 'latest', // Override per environment or deployment
    backendImageTag: 'latest', // Override per environment or deployment
    
    // External Secrets configuration (disabled by default)
    externalSecrets: {
      enabled: false,
      provider: 'vault',
      vault: {
        server: 'http://vault.vault.svc.cluster.local:8200',
        rootToken: 'dev-only-token', // Only for development
      },
    },
    
    // Validation function to ensure required values are set
    assert self.domain != null : 'domain must be set in environment config',
    assert self.storageClass != null : 'storageClass must be set in environment config',
    // caCrt is optional for production when using trusted CAs like Let's Encrypt
  },
  
  // Production configuration
  prod:: self.base {
    domain: 'platform.spezi.stanford.edu',
    loadBalancerIP: staticIP,
    storageClass: 'standard-rwo',
    mode: 'PRODUCTION',
    // Use system CA certificates for production (Let's Encrypt should be trusted by default)
    caCrt: null,
    externalSecrets+: {
      enabled: true,
    },
  },
  
  // Local development configuration  
  localDev(ip=staticIP):: self.base {
    domain: 'spezi.' + ip + '.nip.io',
    loadBalancerIP: ip,
    storageClass: 'standard',
    mode: 'DEV',
    frontendImageTag: 'pr-123',
    backendImageTag: 'pr-17',
    externalSecrets+: {
      enabled: true,
      provider: 'vault',
    },
  },
}
