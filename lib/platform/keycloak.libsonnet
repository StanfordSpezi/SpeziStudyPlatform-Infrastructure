{
  local tanka = import '../../vendor/github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  withConfig(config)::
    {
      keycloak: helm.template('keycloak', '../../charts/keycloak', {
        namespace: config.namespace,
        version: '25.1.1',
        values: {
          global+: {
            security+: {
              allowInsecureImages: true,
            },
          },
          image+: {
            registry: 'docker.io',
            repository: 'bitnamilegacy/keycloak',
          },
          extraEnvVars: [
            {
              name: 'KC_HTTP_RELATIVE_PATH',
              value: '/auth',
            },
            {
              name: 'KC_HOSTNAME',
              value: 'https://' + config.domain + '/auth',
            },
          ] + (
            if std.get(config, 'mode', 'DEV') == 'PRODUCTION' then [
              {
                name: 'KC_PROXY_HEADERS',
                value: 'xforwarded',
              },
              {
                name: 'KC_PROXY',
                value: 'edge',
              },
              {
                name: 'KC_HOSTNAME_STRICT',
                value: 'false',
              },
            ] else [
              {
                name: 'KC_HOSTNAME_STRICT',
                value: 'true',
              },
            ]
          ),
          customReadinessProbe: {
            failureThreshold: 3,
            httpGet: {
              path: '/auth/realms/master',
              port: 8080,
            },
            initialDelaySeconds: 120,
            timeoutSeconds: 5,
          },
          resources: {
            limits: {
              cpu: '1000m',
              memory: '2048Mi',
            },
            requests: {
              cpu: '500m',
              memory: '1024Mi',
            },
          },
          tolerations: [
            {
              key: 'node-role.kubernetes.io/control-plane',
              operator: 'Exists',
              effect: 'NoSchedule',
            },
          ],
          auth: {
            adminPassword: 'admin123!',
          },
          postgresql: {
            global+: {
              security+: {
                allowInsecureImages: true,
              },
            },
            image+: {
              registry: 'docker.io',
              repository: 'bitnamilegacy/postgresql',
            },
            auth: {
              postgresPassword: 'postgres123!',
              password: 'keycloak123!',
            },
            primary: {
              tolerations: [
                {
                  key: 'node-role.kubernetes.io/control-plane',
                  operator: 'Exists',
                  effect: 'NoSchedule',
                },
              ],
            },
          },
          initContainers: |||
            - name: realm-ext-provider
              image: curlimages/curl
              imagePullPolicy: IfNotPresent
              command:
                - sh
              args:
                - -c
                - |
                  curl -L -o /emptydir/app-providers-dir/keycloakify-spezistudyplatform3-theme.jar https://s3.us-west-2.amazonaws.com/ngusav.es/Keycloak+theme+25%2B.jar
              volumeMounts:
                - name: empty-dir
                  mountPath: /emptydir
          |||,
        },
      }),
    },
}
