{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local kustomize = tanka.kustomize.new(std.thisFile),
  withConfig(config)::
    local cnpgManifests = kustomize.build('../../kustomize/cloudnative-pg/');
    // Convert to array if it's an object, otherwise use as is
    local manifestArray = if std.isArray(cnpgManifests) then cnpgManifests else std.objectValues(cnpgManifests);
    local processedManifests = [
      resource
      for resource in manifestArray
      if resource.kind == 'CustomResourceDefinition'
    ];
    {
      [std.strReplace(resource.kind + '-' + resource.metadata.name, '/', '-')]: resource
      for resource in processedManifests
    },
}