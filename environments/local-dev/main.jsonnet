function(component=null, localIP='172.20.117.44') {
  apiVersion: 'tanka.dev/v1alpha1',
  kind: 'Environment',
  metadata: {
    name: 'environments/local-dev',
  },
  spec: {
    namespace: 'default',
    contextNames: ['kind-spezi-study-platform'],
    resourceDefaults: {},
    expectVersions: {},
    applyStrategy: 'server',
    diffStrategy: 'server',
    injectLabels: false,
  },
  data:
    local config = (import '../../lib/platform/config.libsonnet')().localDev(localIP);
    local components = import '../../lib/platform/components.libsonnet';
    components.render(config, component),
}
