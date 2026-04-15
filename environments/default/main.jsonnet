function(component=null) {
  apiVersion: 'tanka.dev/v1alpha1',
  kind: 'Environment',
  metadata: {
    name: 'environments/default',
  },
  spec: {
    namespace: 'default',
    contextNames: ['prod-cluster'],
    resourceDefaults: {},
    expectVersions: {},
    applyStrategy: 'server',
    diffStrategy: 'server',
    injectLabels: false,
  },
  data:
    local config = (import '../../lib/platform/config.libsonnet')().prod;
    local components = import '../../lib/platform/components.libsonnet';
    components.render(config, component),
}
