local kube = import 'kube.libsonnet';
local rules = import "roles.txt";
local config_file = importstr "config.txt";

function(namespace, git_url, git_user, git_password, git_branch)
{
  metadata:: {"namespace": namespace,},
  flux_sa: kube.ServiceAccount("flux") {
    metadata+: $.metadata,
  },

  flux_cmap: kube.ConfigMap("flux-kubeconfig"){
    metadata+: $.metadata,
    data+: {
      config: config_file % {
        "namespace": namespace
      },
    },
  },
  flux_secret: kube.Secret("flux-git-auth") {
     metadata+: $.metadata,
    data_+: {
      "GIT_AUTHKEY": git_password,
      "GIT_AUTHUSER": git_user,
    },
  },
  flux_git_deploy: kube.Secret("flux-git-deploy") {
     metadata+: $.metadata,
  },

  flux_roles: kube.Role("flux") {
     metadata+: $.metadata,
     rules+: rules,
  },
  flux_roleBinding: kube.RoleBinding("flux") {
    metadata+: $.metadata,
    subjects_+: [
      {kind: "ServiceAccount", "metadata": {"name": "flux", "namespace": namespace},},
    ],
    roleRef: {kind: "Role", "name": "flux", "apiGroup": "rbac.authorization.k8s.io"},
  },
  flux_deployment: kube.Deployment("flux") {
    metadata+: $.metadata,
    spec+: {
      replicas: 1,
      revisionHistoryLimit: 0,
      template+: {
      spec+: {
      serviceAccount: "flux",
      volumes_+: {
        "git-keygen": { emptyDir: { medium: "Memory"},},
        "kubeconfig": { configMap: { name: "flux-kubeconfig"},},
        "kubeconfig2": { configMap: { name: "flux-kubeconfig"},},
        "kubecfg": kube.EmptyDirVolume(),
      },
      initContainers_+: {
        kubecfg: kube.Container("kubecfg") {
          image: 'busybox',
          command: [
            '/bin/sh',
            '-c',
            'wget -O /download/kubecfg https://github.com/bitnami/kubecfg/releases/download/v0.15.3/kubecfg-linux-amd64; chmod 755 /download/kubecfg',
          ],
          volumeMounts_+: {
            "kubecfg": {mountPath: "/download"},
          },
        },
      },
      containers_+: {
        flux: kube.Container("flux") {
          image: "docker.io/fluxcd/flux:1.18.0",
          imagePullPolicy: "IfNotPresent",
          resources: {
          requests: { 
            cpu: "50m",
            memory: "64Mi"
          },
          },
          ports_+: {
            "http": {
              "containerPort": 3030,
              "protocol": "TCP",
            },
          },
          livenessProbe: {
            httpGet:{
              path: "/api/flux/v6/identity.pub",
              port: "http",
            },
            initialDelaySeconds: 5,
            timeoutSeconds: 5,
          },
          readinessProbe: {
            httpGet:{
              path: "/api/flux/v6/identity.pub",
              port: "http",
            },
            initialDelaySeconds: 5,
            timeoutSeconds: 5,
          },
          volumeMounts_+: {
            "git-keygen": {mountPath: "/var/fluxd/keygen"},
            "kubeconfig": {mountPath: "/.kube"},
            "kubeconfig2": {mountPath: "/etc/fluxd/kube"},
            "kubecfg": {
               mountPath: "/usr/local/bin/kubecfg",
               subPath: "kubecfg",
            },
         
          },
          env_: {
            "KUBECONFIG": "/etc/fluxd/kube/config",
          },
          envFrom: [
            {"secretRef": {name: "flux-git-auth"}},
          ],
          args_+: {
            "manifest-generation": "true",
            "registry-disable-scanning": "true",
            "ssh-keygen-dir": "/var/fluxd/keygen",
            "git-url": "https://$(GIT_AUTHUSER):$(GIT_AUTHKEY)@"+git_url,
            "git-branch": git_branch,
            "git-label": "flux",
            "git-user": git_user,
            "git-email": "openshiftlab01@gmail.com",
            "listen-metrics": ":3031"
          },
          args+: [
            "--git-readonly",
          ],
        },
      },
    }}},
  },
}
