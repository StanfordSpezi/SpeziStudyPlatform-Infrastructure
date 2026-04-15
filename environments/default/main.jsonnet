function(component=null, env='prod', localIP=null) {
  apiVersion: 'tanka.dev/v1alpha1',
  kind: 'Environment',
  metadata: {
    name: 'environments/default',
  },
  spec: {
    namespace: 'default',
    contextNames: [if env == 'prod' then 'prod-cluster' else 'kind-spezi-study-platform'],
    resourceDefaults: {},
    expectVersions: {},
    applyStrategy: 'server',
    diffStrategy: 'server',
    injectLabels: false,
  },
  data:
    local cfgLib = (import '../../lib/platform/config.libsonnet')();
    local config = if env == 'prod' then cfgLib.prod else cfgLib.localDev(localIP);
    local components = import '../../lib/platform/components.libsonnet';
    components.render(config, component),
}
