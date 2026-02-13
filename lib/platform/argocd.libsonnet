{
  local k = import 'k.libsonnet',
  withConfig(config)::
    local oidcConfig = |||
      name: Keycloak
      issuer: https://%(domain)s/auth/realms/spezistudyplatform
      clientId: argocd
      redirectURI: https://%(domain)s/argo/auth/callback
      enablePKCEAuthentication: true
      insecure: true
      requestedScopes: ["openid", "profile", "email", "groups"]
      requestedIDTokenClaims:
        groups:
          essential: true
      cliClientId: argocd
    ||| % { domain: config.domain };
    {
      // ArgoCD Ingress Route with OAuth2-proxy integration
      argocd_oauth_middleware: {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: 'oauth2-proxy-argo',
          namespace: config.namespace,
        },
        spec: {
          forwardAuth: {
            address: 'http://oauth2-proxy.' + config.namespace + '.svc.cluster.local/oauth2/auth?allowed_groups=ArgoCDAdmins',
            trustForwardHeader: true,
            authResponseHeaders: [
              'X-Forwarded-User',
              'X-Forwarded-Email',
              'X-Forwarded-Groups',
              'X-Forwarded-Preferred-Username',
            ],
            authRequestHeaders: [],
          },
        },
      },

      // oauth2-errors middleware already exists from traefik component

      argocd_tls_certificate: {
        apiVersion: 'cert-manager.io/v1',
        kind: 'Certificate',
        metadata: {
          name: 'argocd-main-tls-cert',
          namespace: 'argocd',
        },
        spec: {
          commonName: config.domain,
          secretName: 'spezistudyplatform-main-tls-secret',
          issuerRef: {
            name: if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'letsencrypt-prod' else 'selfsigned-issuer',
            kind: 'ClusterIssuer',
          },
          dnsNames: [
            config.domain,
          ] + (if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then [] else ['spezi.127.0.0.1.nip.io']),
        },
      },

      argocd_ingress_route: {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'IngressRoute',
        metadata: {
          name: 'argocd-ingress',
          namespace: 'argocd',
          annotations: {
            'cert-manager.io/cluster-issuer': if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then 'letsencrypt-prod' else 'selfsigned-issuer',
          },
        },
        spec: {
          entryPoints: ['websecure'],
          routes: [
            {
              kind: 'Rule',
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/argo`)',
              priority: 10,
              services: [
                {
                  name: 'argocd-server',
                  port: 80,
                },
              ],
            },
            {
              kind: 'Rule', 
              match: 'Host(`' + config.domain + '`) && PathPrefix(`/argo`) && Header(`Content-Type`, `application/grpc`)',
              priority: 10,
              services: [
                {
                  name: 'argocd-server',
                  port: 80,
                  scheme: 'h2c',
                },
              ],
            },
          ],
          tls: {
            secretName: 'spezistudyplatform-main-tls-secret',
          },
        },
      },

      // ArgoCD OIDC configuration
      argocd_oidc_config: k.core.v1.configMap.new('argocd-cmd-params-cm', {
        'server.insecure': 'true',
        'server.basehref': '/argo',
        'server.rootpath': '/argo',
      })
      + k.core.v1.configMap.metadata.withNamespace('argocd'),

      // Complete argocd-cm ConfigMap with both resource exclusions and OIDC configuration
      argocd_cm_complete: {
        apiVersion: 'v1',
        kind: 'ConfigMap',
        metadata: {
          name: 'argocd-cm',
          namespace: 'argocd',
          labels: {
            'app.kubernetes.io/name': 'argocd-cm',
            'app.kubernetes.io/part-of': 'argocd',
          },
        },
        // TODO: This shouldn't need to be specified so exhaustively here, per https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/keycloak/#keycloak-and-argocd-with-pkce. 
        // come back and clean this up eventually. It's not harmful, just ugly!
        data: {
          'url': 'https://' + config.domain + '/argo',
          'oidc.config': oidcConfig,
        } + {
          'resource.customizations.ignoreResourceUpdates.ConfigMap': |||
            jqPathExpressions:
              - '.metadata.annotations."cluster-autoscaler.kubernetes.io/last-updated"'
              - '.metadata.annotations."control-plane.alpha.kubernetes.io/leader"'
          |||,
          'resource.customizations.ignoreResourceUpdates.Endpoints': |||
            jsonPointers:
              - /metadata
              - /subsets
          |||,
          'resource.customizations.ignoreResourceUpdates.all': |||
            jsonPointers:
              - /status
          |||,
          'resource.customizations.ignoreResourceUpdates.apps_ReplicaSet': |||
            jqPathExpressions:
              - '.metadata.annotations."deployment.kubernetes.io/desired-replicas"'
              - '.metadata.annotations."deployment.kubernetes.io/max-replicas"'
              - '.metadata.annotations."rollout.argoproj.io/desired-replicas"'
          |||,
          'resource.customizations.ignoreResourceUpdates.argoproj.io_Application': |||
            jqPathExpressions:
              - '.metadata.annotations."notified.notifications.argoproj.io"'
              - '.metadata.annotations."argocd.argoproj.io/refresh"'
              - '.metadata.annotations."argocd.argoproj.io/hydrate"'
              - '.operation'
          |||,
          'resource.customizations.ignoreResourceUpdates.argoproj.io_Rollout': |||
            jqPathExpressions:
              - '.metadata.annotations."notified.notifications.argoproj.io"'
          |||,
          'resource.customizations.ignoreResourceUpdates.autoscaling_HorizontalPodAutoscaler': |||
            jqPathExpressions:
              - '.metadata.annotations."autoscaling.alpha.kubernetes.io/behavior"'
              - '.metadata.annotations."autoscaling.alpha.kubernetes.io/conditions"'
              - '.metadata.annotations."autoscaling.alpha.kubernetes.io/metrics"'
              - '.metadata.annotations."autoscaling.alpha.kubernetes.io/current-metrics"'
          |||,
          'resource.customizations.ignoreResourceUpdates.discovery.k8s.io_EndpointSlice': |||
            jsonPointers:
              - /metadata
              - /endpoints
              - /ports
          |||,
          'resource.customizations.ignoreResourceUpdates.external-secrets.io_PushSecret': |||
            jsonPointers:
              - /status
          |||,
          'resource.exclusions': |||
            ### Network resources created by the Kubernetes control plane and excluded to reduce the number of watched events and UI clutter
            - apiGroups:
              - ''
              - discovery.k8s.io
              kinds:
              - Endpoints
              - EndpointSlice
            ### Internal Kubernetes resources excluded reduce the number of watched events
            - apiGroups:
              - coordination.k8s.io
              kinds:
              - Lease
            ### Internal Kubernetes Authz/Authn resources excluded reduce the number of watched events
            - apiGroups:
              - authentication.k8s.io
              - authorization.k8s.io
              kinds:
              - SelfSubjectReview
              - TokenReview
              - LocalSubjectAccessReview
              - SelfSubjectAccessReview
              - SelfSubjectRulesReview
              - SubjectAccessReview
            ### Intermediate Certificate Request excluded reduce the number of watched events
            - apiGroups:
              - certificates.k8s.io
              kinds:
              - CertificateSigningRequest
            - apiGroups:
              - cert-manager.io
              kinds:
              - CertificateRequest
            ### Cilium internal resources excluded reduce the number of watched events and UI Clutter
            - apiGroups:
              - cilium.io
              kinds:
              - CiliumIdentity
              - CiliumEndpoint
              - CiliumEndpointSlice
            ### Kyverno intermediate and reporting resources excluded reduce the number of watched events and improve performance
            - apiGroups:
              - kyverno.io
              - reports.kyverno.io
              - wgpolicyk8s.io
              kinds:
              - PolicyReport
              - ClusterPolicyReport
              - EphemeralReport
              - ClusterEphemeralReport
              - AdmissionReport
              - ClusterAdmissionReport
              - BackgroundScanReport
              - ClusterBackgroundScanReport
              - UpdateRequest
          |||,
        },
      },

      argocd_server_config: k.core.v1.configMap.new('argocd-server-config', {
        'url': 'https://' + config.domain + '/argo',
      })
      + k.core.v1.configMap.metadata.withNamespace('argocd'),

      argocd_rbac_cm: k.core.v1.configMap.new('argocd-rbac-cm', {
        'policy.default': 'role:readonly',
        'policy.csv': std.join('\n', [
          'p, role:admin, applications, *, */*, allow',
          'p, role:admin, certificates, *, *, allow', 
          'p, role:admin, clusters, *, *, allow',
          'p, role:admin, repositories, *, *, allow',
          'g, ArgoCDAdmins, role:admin',
        ]),
      })
      + k.core.v1.configMap.metadata.withNamespace('argocd'),

      

      // Note: ArgoCD OIDC client secret will be managed separately through Keycloak client secret
    }
}