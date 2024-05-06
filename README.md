# Elastic-HPC

Elastic HPC is the deployment of multiple Magic Castle (MC) cluster on the SD4H infrastructure. [This repo](https://github.com/c3g/magic_castle) is the template to be able to add a new cluster in the project or to manage an existing one.

The fork we use to deploy MC stays as close as possible to the upstream project for both the [Terrafrom repos](https://github.com/c3g/magic_castle) and its accompanying  [puppet configuration](https://github.com/c3g/puppet-magic_castle). Hopefully, we will be able to merge all our required feature to the upstream project in the future and Elastic-HPC will only need a specific configuration included in this template to be deployed.


The elastic-HPC clusters are deployed in a single OpenStack Project or tenant: `Elastic-HPC` and managed by the SD4H team on the [SD4H/Juno infrastructure](https://www.sd4health.ca/).

Every deployment has it own private network and Slurm deployment. However there is a shared network for the CephFS file system that also needs to be mounted on all the Magic Castle nodes. The presence and mounting of this second network for the CephFS on all the clusters' hosts is the biggest difference between this version of Magic Castle and the upstream.


## Current deployment

The current deployment allocation is maintained here [this spreadsheet](https://docs.google.com/spreadsheets/d/15T0ea7qq-4mbekLgbJNQ0GMcPukT-wFqBYuNZ5VHv5w/edit#gid=0
). You can see how much resources are available for all deployed clusters. Right now that part is manual.

You can also have a look at the Elastic-HPC project on the [SD4H/Juno OpenStack webpage](https://juno.calculquebec.ca/)

Then there is the terraform state of the clusters stored in the Elastic-HPC object store's `git-repos` bucket. The repo itself is `elastic-hpc.git`. It can be copied locally a and then clone to main. The procedure is clunky procedure. Hopefully, it will get better with time.


## Adding a new project.

You will need to [install the terraform client](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli) on your machine do the deployment since Magic Castle is a Terraform project!

You also need to be part of the elastic-HPC project on OpenStack. You can request it to [juno@calculquebec.ca](mailto:juno@calculquebec.ca)

You also need to have access to the [c3g cloudflare](www.cloudflare.com) account or at least access to a token that will let you edit the [sd4h.ca](sd4h.ca) DNS. Right now P-O Quirion and Victor Rocheleau can produce tokens and have access to the account.

### Setting up the terraform plan

#### A new name
 Find a name for the new cluster (right now we ask Marieke for a new bird name :) ).
#### Tell everyone
Update the [this spreadsheet](https://docs.google.com/spreadsheets/d/15T0ea7qq-4mbekLgbJNQ0GMcPukT-wFqBYuNZ5VHv5w/edit#gid=0) with the new project.
#### Configure the OpenStack and the Terraform config

We do a step-by-step description of the creation of a new Cluster in the Elastic-HPC project.
It would be similar when creating a cluster in a separate project.  The cluster here will be named corbeau.

1. Create the new Home and Project CephFS share:


```bash
CLUSTER_NAME=corbeau
OS_CLOUD=Elastic-HPC # See how to set you cloud.yaml config here https://docs.openstack.org/python-openstackclient/pike/configuration/index.html
HOME_SIZE=50 # in GB, usually 50GB per user
PROJECT_SIZE=50 # in GB, where the computation happens
# Create the shares themselves
openstack share create --share-type cephfs-ec42  --availability-zone nova  --name "$CLUSTER_NAME-home"   --description "$CLUSTER_NAME home, this is a test cluster"  cephFS $HOME_SIZE
openstack share create --share-type cephfs-ec42  --availability-zone nova  --name "$CLUSTER_NAME-project"   --description "$CLUSTER_NAME project, this is a test cluster"  cephFS $PROJECT_SIZE
# Create a WR access to the share, we give it the same name has the share itself, parce-que bon!
openstack share  access create $CLUSTER_NAME-home cephx $CLUSTER_NAME-home
openstack share  access create $CLUSTER_NAME-project cephx $CLUSTER_NAME-project
```



2. Create a new virtual network

This step is necessary to isolate `corbeau` from the other cluster deployed in
the project.

```bash
# Create a network and a subnet
openstack network create $CLUSTER_NAME-net
openstack subnet create $CLUSTER_NAME-subnet --network $CLUSTER_NAME-net  --subnet-pool subnet_pool
#attatch subnet to router
openstack router add subnet Elastic-HPC_router $CLUSTER_NAME-subnet
```


3. Get the Elastic-HPC terraform template:

The template for the clusters is provided along the README you are currently reading [here](https://github.com/c3g/elastic-HPC), you are mostly safe if you use it from the tip of the `main` branch.

```bash
BRANCH=main
wget -qO- https://github.com/c3g/elastic-HPC/archive/${BRANCH}.tar.gz | tar xvz  --transform "s/^elastic-HPC-${BRANCH}/$CLUSTER_NAME/"
```  

4. Configure the `main.tf` file

Add your public ssh key to the public_keys list. Right now P-O Quirion, from the C3G, is there by default, leave it there, I might need to help at some point :).

Set the cluster name, resources and subnet_id in the `$CLUSTER_NAME/main.tf` file.  You can get the subnet_id with this command:

```bash
openstack subnet show -c id -c name    $CLUSTER_NAME-subnet
```

You need one `mgmt-` and one login node at least, deploy these two VM in the HA room by selecting the right flavour.
You can list all available flavour like this:

```bash
openstack flavour list
```

Name the login node the same has the cluster itself, so you
know where you are when you login. Add also at least one compute or GPU node.
Make sure that the nodes all have ephemeral disks in their flavour/type.

Here is a typical example of with a single compute node with `32` cores, `120 GB`
of ram and an `400 GB` ephemeral SSD disk.   

``` bash
mgmt   = { type = "ha4-15gb-50", tags = ["puppet", "mgmt","cephfs"], count = 1, disk_size= 20  }
corbeau-  = { type = "ha2-7.5gb-25", tags = ["login", "public", "proxy","cephfs"], count = 1 }
node-   = { type = "c32-120gb-400", tags = ["node","cephfs"], count = 1 }
```

You can leave the count to 0 in for the unwanted type of nodes. Note that we
will be able to add and remove compute and GPU nodes with time. This makes
this project truly elastic.

5. Configure the   `config.yml` file

We attach the CephFS share by configuring the `$CLUSTER_NAME/config.yml`file.

The export path is the value returned by `export_locations.path` by this command:

```bash
openstack share  show $CLUSTER_NAME-home
openstack share  show $CLUSTER_NAME-project

```

Here is an example for the `corbeau` cluster's `/home` directory:

```bash
# Get the export path
$openstack share  show -c export_locations -c name $CLUSTER_NAME-home
+------------------+-----------------------------------------------------------------------------------------------------------------+
| Field            | Value                                                                                                           |
+------------------+-----------------------------------------------------------------------------------------------------------------+
| export_locations |                                                                                                                 |
|                  | id = 398e9ee4-d141-4a95-bf0d-40985348de54                                                                       |
|                  | path = 10.65.0.10:6789,10.65.0.12:6789,10.65.0.11:6789:/volumes/_nogroup/long-UID/another-UID |
|                  | preferred = False                                                                                               |
| name             | corbeau-home                                                                                                    |
+------------------+-----------------------------------------------------------------------------------------------------------------+
# Then the access_key
$openstack share  access   list -c 'Access To' -c 'Access Key'  $CLUSTER_NAME-home
+--------------+------------------------------------------+
| Access To    | Access Key                               |
+--------------+------------------------------------------+
| corbeau-home | xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx== |
+--------------+------------------------------------------+

```

```yaml
profile::ceph::client::shares:
  home
    share_name: "corbeau-home"
    access_key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx==
    export_path: /volumes/_nogroup/long-UID/another
    bind_mounts:
      - src: "/"
        dst: "/project"
        type: "directory"
  project
    [...]   
```



Still in `$CLUSTER_NAME/config.yml`, set all the users that will have access to the cluster with their username and public ssh key, you also need to add their Globus id if you plan to deploy Globus with your cluster. The UNIX group has to match `(ctb|def|rpp|rrg)-[a-z0-9_-]*` to be used with SLURM. This means that other group can still be created to manage data but will not be valid to submit SLURM jobs.  

Here is an example configuration without a Globus access :

```yaml
profile::users::ldap::users:
  poq:
    groups: ['def-project']
    public_keys: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKNh8QVIYdqgnPK1jS2slJ7Xmcz3eEfqGRaSKqKK3gSF poq@laptop.pub.key
  ti-jean:
    [...]

```

### Applying the plan
In the terminal run

```bash
$terraform init
$terraform apply
```

Look at the output and type `yes` if you are happy with what you see. In case of troubles, request some help on the C3G SD4H slack channel!


## Scaling

To change the size of the cluster, change the count value in the main.tf for the compute or GPU nodes. Do not change the mgmt or login node count value then run `terraform apply`.  


## Future
### Auto Scaling
### Easy Onboarding
