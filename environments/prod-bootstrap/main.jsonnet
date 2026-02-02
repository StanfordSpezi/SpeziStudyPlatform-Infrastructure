function(gitBranch='main')
local argocdApps = import '../../lib/platform/argocd-apps.libsonnet';
// Production ArgoCD bootstrap configuration
local config = (import '../../lib/platform/config.libsonnet')().prod + { gitBranch: gitBranch };
argocdApps.withConfig(config)