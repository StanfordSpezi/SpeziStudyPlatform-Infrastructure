{
  withConfig(config)::
    local keycloak = import './keycloak.libsonnet';
    local oauth2Proxy = import './oauth2-proxy.libsonnet';
    local authIngress = import './auth-ingress.libsonnet';
    
    // Combine all auth-related components
    // keycloak and oauth2Proxy return arrays, authIngress returns object
    local keycloakResources = keycloak.withConfig(config);
    local oauth2ProxyResources = oauth2Proxy.withConfig(config);
    local authIngressResources = authIngress.withConfig(config);
    
    // Return combined object of all resources
    std.foldl(function(a, b) a + b, [keycloakResources, oauth2ProxyResources, authIngressResources], {}),
}