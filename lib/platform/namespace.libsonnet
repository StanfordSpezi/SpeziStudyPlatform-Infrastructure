{
  withConfig(config):: {
    ['Namespace-' + config.namespace]: {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: config.namespace,
      },
    },
  },
}