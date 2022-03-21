# Unmanaged Clusters Reference

This is the reference documentation for the `unmanaged-cluster` plugin. If
this is your first time deploying an unmanaged cluster, see
[Getting Started with Unmanaged Clusters](getting-started-unmanaged/).

## Command aliases

As a Tanzu CLI plugin, unmanaged clusters can be interacted with using `tanzu
unmanaged-cluster`. `uc`, `um`, and `unmanaged` are all valid aliases for the
command. This means the following commands equate to the same:

* `tanzu unmanaged-cluster create hello`
* `tanzu uc create hello`
* `tanzu um create hello`
* `tanzu unmanaged create hello`

## Creating clusters

`create` is used to create a new cluster. By default, it:

1. Installs a cluster using `kind`.
1. Installs `kapp-controller`.
1. Installs a core package repository.
1. Installs a user-managed package repository.
1. Installs a CNI package.
    * defaults to `calico`.
1. Sets your kubeconfig context to the newly created cluster.

To create a cluster, run:

```sh
tanzu unmanaged-cluster create ${CLUSTER_NAME}
```

## Deploy multi-node clusters

`create` supports `--control-plane-node-count`
and `--worker-node-count` to create multi-node clusters in a supported provider.

_Note:_ The `kind` provider does _not_ support deploying multiple control planes
with no worker nodes. For this type of granular configuration, see [Customize cluster provider.](#customize-cluster-provider)

The following example deploys 5 total nodes
using the default `kind` provider

```sh
tanzu unmanaged-cluster create --control-plane-node-count 2 --worker-node-count 3
```

## Listing clusters

`list` or `ls` is used to list all known clusters. To list known clusters, run:

```sh
tanzu unmanaged-cluster list
```

## Deleting clusters

`delete` or `rm` is used to delete a cluster. It will:

1. Attempt to delete the cluster based on the provider.
    * by default, clusters use `kind`, this will delete the `kind` cluster.
1. Attempt to remove the cluster's directory.
    * located at `~/.config/tanzu/tkg/unmanaged/${CLUSTER_NAME}/`.

To delete a cluster, run:

```sh
tanzu unmanaged-cluster delete ${CLUSTER_NAME}
```

## Custom configuration

`configure`, `config`, or `conf` creates a configuration file for cluster creation:

```sh
tanzu unmanaged-cluster configure ${CLUSTER_NAME}
```

This will create a configuration file, which you can modify to change how
clusters are created. When creating a cluster, the `-f` flag can be used to
specify this configuration file.

Along with a configuration file, `unmanaged-cluster` respects settings from
other settings such as flags. The order in which settings are resolved is:

1. Defaults (lowest precedence)
1. Configuration File
1. Environment Variables
1. Flags (highest precedence)

As a result of rendering the above, a final configuration file is persisted to:

`~/.config/tanzu/tkg/unmanaged/${CLUSTER_NAME}/config.yaml`

Reviewing this file can help in troubleshooting issues during cluster
bootstrapping.

## Customize cluster provider

Use the `ProviderConfiguration` field in the configuration file
to give provider specific and granular customizations.
Note that _ALL_ other provider specific configs are ignored
when `ProviderConfiguration` is used.

* Kind provider: Use the `rawKindConfig` field to enter an entire [`kind` configuration file](https://kind.sigs.k8s.io/docs/user/configuration/)
  to be used when bootstrapping. For example, the following config
  deploys a control plane with port mappings and 2 worker nodes,
  all using the VMware hosted kind image.

  ```yaml
  ClusterName: test
  KubeconfigPath: ""
  ExistingClusterKubeconfig: ""
  NodeImage: ""
  Provider: kind
  ProviderConfiguration:
    rawKindConfig: |
      kind: Cluster
      apiVersion: kind.x-k8s.io/v1alpha4
      nodes:
      - role: control-plane
        image: projects.registry.vmware.com/tce/kind/node:v1.22.5
        extraPortMappings:
        - containerPort: 888
          hostPort: 888
          listenAddress: "127.0.0.1"
          protocol: TCP
        - role: worker
          image: projects.registry.vmware.com/tce/kind/node:v1.22.5
        - role: worker
          image: projects.registry.vmware.com/tce/kind/node:v1.22.5
  Cni: calico
  CniConfiguration: {}
  PodCidr: 10.244.0.0/16
  ServiceCidr: 10.96.0.0/16
  TkrLocation: projects.registry.vmware.com/tce/tkr:v1.21.5
  SkipPreflight: false
  ```

## Install to existing cluster

If you wish to install the Tanzu components, such as `kapp-controller` and the
package repositories into an **existing** cluster, you can do so with the
`--existing-cluster-kubeconfig`/`e` flags or `existingClusterKubeconfig`
configuration field. The following example demonstrates installing into an
existing [minikube](https://minikube.sigs.k8s.io) cluster.

1. Create a `minikube` cluster.

    ```sh
    $ minikube start

    * minikube v1.24.0 on Arch rolling
    * Automatically selected the docker driver. Other choices: kvm2, ssh
    * Starting control plane node minikube in cluster minikube
    * Pulling base image ...

    * Preparing Kubernetes v1.22.3 on Docker 20.10.8 ...
      - Generating certificates and keys ...
      - Booting up control plane ...
      - Configuring RBAC rules ...
    * Verifying Kubernetes components...
      - Using image gcr.io/k8s-minikube/storage-provisioner:v5
    * Enabled addons: storage-provisioner, default-storageclass
    * Done! kubectl is now configured to use "minikube" cluster and "default" namespace by default
    ```

1. Install the unmanaged cluster components

    ```sh
    tanzu unmanaged-cluster create -e ~/.kube/config --cni=none
    ```

    * `~/.kube/config` is the location of the kubeconfig used to access the
      `minikube` cluster.
    * `--cni=none` is set since `minikube` already sets up a network for pods.

1. Now you can use the `tanzu` CLI to interact with the cluster.

    ```sh
    tanzu package list -A
    ```

## Disable CNI installation

To create a cluster **without** a CNI installed, run:

```sh
tanzu unmanaged-cluster create --cni=none
```

This will skip CNI installation and prompt the following during the CNI
installation step.

```txt
🌐 Installing CNI
   No CNI installed: CNI was set to none.
```

The cluster creation will complete successfully. After that, you are free to
install a CNI into the cluster.

## Customize the distribution

Unmanaged clusters gather details on how to create a cluster from a Tanzu
Kubernetes Release (TKr) file. For each release of unmanaged clusters, a
[default TKr is
set](https://github.com/vmware-tanzu/community-edition/blob/d0a8622e164c1e345686470b7bcce0c6be9c58f5/cli/cmd/plugin/unmanaged-cluster/tkr/tkr.go#L14-L16).

When creating clusters, you can point to a different TKr using the `--tkr` flag.
The TCE project keeps TKrs for unmanaged clusters at
`projects.registry.vmware.com/tce/tkr`. Using
[imgpkg](https://carvel.dev/imgpkg), you can query available TKrs using:

```sh
$ imgpkg tag list -i projects.registry.vmware.com/tce/tkr
Tags

Name
sha256-2fd337282cf17357c6329f441dc970ec900145faef9e2ec6122f98fa75d529c3.imgpkg
sha256-33f63314fb72ead645715f6ac85128c0fe0fd380d14f0a79eddba3dd361b73dd.imgpkg
sha256-ac6566268e0f113a4b91bab870a34353685e886f97e248633bb2c2fcf6490dc8.imgpkg
v1.21.5
v1.21.5-1
v1.21.5-2
v1.21.5-3
v1.22.2
```

To create a cluster with an alternative TKr, you can run:

```sh
tanzu unmanaged-cluster create --tkr projects.registry.vmware.com/tce/tkr:v1.22.2
```

To customize a TKr, you can pull an existing one down using `imgpkg`:

```sh
$ imgpkg pull -i projects.registry.vmware.com/tce/tkr:v1.22.2 -o tkr
Pulling image 'projects.registry.vmware.com/tce/tkr@sha256:7c1a241dc57fe94f02be4dd6d7e4b29f159415417164abc4b5ab6bb10cf4cbaa'
Extracting layer 'sha256:e17e901811682a2c8c91c8865f3344a21fdf8f83f012de167c15d2ab06cc494a' (1/1)

Succeeded
```

You can then edit the above TKr in the `tkr/tkr-bom-v1.22.2.yaml`. After
modifying it, you may also wish to rename the YAML file. Once you have made your
modifications, you can repush it using:

```sh
imgpkg push -f ./tkr/tkr-bom-CUSTOM.yaml -i ${YOUR_REGISTRY}:${YOUR_TAG}
```

Once pushed, you can reference this repo using the `--tkr` flag.

## Exit codes

Unmanaged clusters provide meaningful exit codes.
These are useful when deploying `unmanaged-cluster` in automation or CI/CD.
To see the exit code of a process, execute `echo $?`.

The exit codes are defined as follows:

* 0  - Success.
* 1  - Configuration is invalid.
* 2  - Could not create local cluster directories.
* 3  - Unable to get TKR BOM.
* 4  - Could not render config.
* 5  - TKR BOM not parseable.
* 6  - Could not resolve kapp controller bundle.
* 7  - Unable to create cluster.
* 8  - Unable to use existing cluster (if provided).
* 9  - Could not install kapp controller to cluster.
* 10 - Could not install core package repo to cluster.
* 11 - Could not install additional package repo
* 12 - Could not install CNI package.
* 13 - Failed to merge kubeconfig and set context

## Limitations

This section details known limitations of unmanaged clusters.

### Can't Upgrade Kubernetes

By design, `unmanaged-clusters` do not lifecycle-manage Kubernetes. They are not
meant to be long-running with real workloads. To change Kubernetes versions,
delete the existing cluster and create a new cluster with a different
configuration.

### Deploying to Windows

`kind`, the default provider,
has several known limitations when deploying to Windows.
For example, deploying a [load balancer has networking considerations.](https://kind.sigs.k8s.io/docs/user/loadbalancer/)
Be sure to familiarize yourself with the [`kind` documentation](https://kind.sigs.k8s.io/)
in order to [customize your unmanaged-cluster deployment](#custom-configuration) for your needs.