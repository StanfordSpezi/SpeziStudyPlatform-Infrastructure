// Shared component registry used by all Tanka environments.
// Each component is a Jsonnet library that accepts a config object.
{
  withConfig(config):: {
    namespace: (import 'namespace.libsonnet').withConfig(config),
    'cert-manager': (import 'cert-manager.libsonnet').withConfig(config),
    'cloudnative-pg-crds': (import 'cloudnative-pg-crds.libsonnet').withConfig(config),
    'cloudnative-pg': (import 'cloudnative-pg.libsonnet').withConfig(config),
    'external-secrets': (import 'external-secrets.libsonnet').withConfig(config),
    server: (import 'server.libsonnet').withConfig(config),
    web: (import 'web.libsonnet').withConfig(config),
    traefik: (import 'traefik.libsonnet').withConfig(config),
    auth: (import 'auth.libsonnet').withConfig(config),
    argocd: (import 'argocd.libsonnet').withConfig(config),
  },

  // Render one component or all, based on the component parameter.
  render(config, component=null)::
    local components = self.withConfig(config);
    if component != null then
      if std.objectHas(components, component) then
        components[component]
      else
        error 'Component "' + component + '" not found. Available: ' + std.join(', ', std.objectFields(components))
    else
      std.foldl(function(a, b) a + b, std.objectValues(components), {}),
}
