function(component=null) {
  apiVersion: 'tanka.dev/v1alpha1',
  kind: 'Environment',
  metadata: {
    name: 'environments/default',
  },
  spec: {
    namespace: 'default',
    contextNames: ['prod-cluster'], // Update for prod context
    resourceDefaults: {},
    expectVersions: {},
    applyStrategy: 'server',
    diffStrategy: 'server',
    injectLabels: false,
  },
  data:
    // Production environment configuration
    local config = (import '../../lib/platform/config.libsonnet')().prod;
    local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
    local kustomize = tanka.kustomize.new(std.thisFile);
    local namespace = import '../../lib/platform/namespace.libsonnet';
    local certManager = import '../../lib/platform/cert-manager.libsonnet';
    local cloudnativePgCrds = import '../../lib/platform/cloudnative-pg-crds.libsonnet';
    local cloudnativePg = import '../../lib/platform/cloudnative-pg.libsonnet';
    local backend = import '../../lib/platform/backend.libsonnet';
    local frontend = import '../../lib/platform/frontend.libsonnet';
    local traefik = import '../../lib/platform/traefik.libsonnet';
    local auth = import '../../lib/platform/auth.libsonnet';
    local externalSecrets = import '../../lib/platform/external-secrets.libsonnet';
    local argocd = import '../../lib/platform/argocd.libsonnet';
    // Note: argocd-apps is not included here, it's used to generate the apps that point to this env.

    local components = {
      namespace: namespace.withConfig(config),
      'cert-manager': certManager.withConfig(config),
      'cloudnative-pg-crds': cloudnativePgCrds.withConfig(config),
      'cloudnative-pg': cloudnativePg.withConfig(config),
      'external-secrets': externalSecrets.withConfig(config),
      backend: backend.withConfig(config),
      frontend: frontend.withConfig(config),
      traefik: traefik.withConfig(config),
      auth: auth.withConfig(config),
      argocd: argocd.withConfig(config),
    };

    if component != null then
      if std.objectHas(components, component) then
        components[component]
      else
        error 'Component "' + component + '" not found. Available components: ' + std.join(', ', std.objectFields(components))
    else
      // If no component is specified, render all of them.
      std.foldl(function(a, b) a + b, std.objectValues(components), {}),
}
