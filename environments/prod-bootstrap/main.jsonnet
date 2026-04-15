function(gitBranch='main')
local argocdApps = import '../../lib/platform/argocd-apps.libsonnet';
local config = (import '../../lib/platform/config.libsonnet')().prodBootstrap + { gitBranch: gitBranch };
argocdApps.withConfig(config)
