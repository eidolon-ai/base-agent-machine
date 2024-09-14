# Advanced kubernetes setup

This document is for advanced users who want to set up the Eidolon agent machine in a cloud based k8s environment, in production, or just want to learn what is going on in the Makefile.

There are two make targets in the makefile, `k8s-operator` and `k8s-serve`.

The `k8s-operator` target installs the Eidolon operator in your k8s cluster. This only needs to be done once. It is executing the following commands:

* It first checks if `helm` and `kubectl` are installed.
* It then checks the permissions of the current user to see if they can install the operator by running `./verify_k8s`.
* If you are NOT using Minikube locally, set the environment variable `DOCKER_REPO_URL` to the proper location.
  * Linux/OSX: `export DOCKER_REPO_URL=<ip>:5000/my-eidolon-project`
  * Windows (PowerShell): `$env:DOCKER_REPO_URL="<ip>:5000/my-eidolon-project"`
* It then checks if the operator is already installed. If not, it installs the operator by running:
  * `helm repo add eidolon https://eidolonai.com/charts`
  * `helm install eidolon eidolon/eidolon-operator-chart`
* It does not try to update the operator. If you want to update the operator, you will need to run `helm upgrade eidolon eidolon/eidolon-operator-chart`.
* If you are not running locally, then make sure to ignore the machine file to avoid checking in by running `git update-index --assume-unchanged k8s/ephemeral_machine.yaml`.

These command should work for either a local k8s environment or a cloud based k8s environment.

The `k8s-serve` target builds the agent docker image and installs the Eidolon agent machine, and all other yaml files in the resources directory, in your k8s cluster.

There are builtin assumptions that make local development easier but prevents remote development. Particularly, the scripts rely on the local image names and the image is not pushed
to a remote repository. This is because the image is built and pushed to the local docker daemon and the k8s cluster is configured to use the local docker daemon.

If you want to use a remote docker repository, you will need to modify the `resources/ephemeral_machine.yaml.yaml` file to use a remote image name, 
and you will need to push the image to the remote repository when building the docker image. You may also need to adjust the ImagePullPolicy from its default value of `IfNotPresent` to `Always`.
