terraform {
  required_version = ">= 1.4.0"
}


variable "pool" {
  description = "Slurm pool of compute nodes"
  default = []
}

module "openstack" {
  source         = "git::https://github.com/C3G/magic_castle.git//openstack?ref=main"
  config_git_url = "https://github.com/c3g/puppet-magic_castle.git"
  config_version = "main"

  cluster_name = "<HPC_NAME>"
  domain       = "sd4h.ca"
  image        = "AlmaLinux-8.9-x64-2023-11"

  instances = {
    mgmt   = { type = "ha8-30gb-100", tags = ["puppet", "mgmt","cephfs"], count = 1, disk_size= 50  }
    cardinal-  = { type = "ha8-30gb-100", tags = ["login", "public", "proxy","cephfs"], count = 1 }
    globus  = { type = "ha4-15gb", tags =  [ "public","dtn","cephfs"], count = 1 }
    node-   = { type = "c64-240gb-800", tags = ["node","cephfs"], count = 1 }
    node-hm-   = { type = "c64-480gb-800", tags = ["node","cephfs"], count = 0 }
    gpu-node-   = { type = "gpu12-120-850gb-a100x1", tags = ["node","cephfs"], count = 0 }
    to-clone- = { type = "c2-7.5gb", tags = ["node","cephfs"], count = 0}
 }

subnet_id= "<subnet_id>"
hieradata = file("config.yaml")
os_ext_network= "Public-Network"
  

  public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKNh8QVIYdqgnPK1jS2slJ7Xmcz3eEfqGRaSKqKK3gSF poq@frugal"]

 pool = var.pool
 # No nfs mounted volumes
 volumes ={}
 # only open's proxy to C3G offices ip's by default
 firewall_rules = {
    ssh = { "from_port" = 22, "to_port" = 22, "tag"= "login" }
    http_genome = { "from_port"= 80, "to_port" = 80, "tag" = "proxy", "cidr" = "132.216.77.22/32"}
    https_genome = { "from_port" = 443, "to_port" = 443, "tag" = "proxy", "cidr" = "132.216.77.22/32" }
    http_1010 = { "from_port"= 80, "to_port" = 80, "tag" = "proxy", "cidr" = "142.157.245.142/32"}
    https_1010 = { "from_port" = 443, "to_port" = 443, "tag" = "proxy", "cidr" = "142.157.245.142/32" }
    Globus = { "from_port" = 443, "to_port" = 443, "tag" = "dtn" }
    GridFTP = { "from_port" = 50000, "to_port" = 51000, "tag" = "dtn" }
  }

 # no token user created	
  nb_users = 0
  # Shared password, randomly chosen if blank
  guest_passwd = ""

}

output "accounts" {
  value = module.openstack.accounts
}

output "public_ip" {
  value = module.openstack.public_ip
}

## Uncomment to register your domain name with CloudFlare
module "dns" {
  source           = "git::https://github.com/C3G/magic_castle.git//dns/cloudflare"
  name             = module.openstack.cluster_name
  bastions         = module.openstack.bastions
  domain           = module.openstack.domain
  public_instances = module.openstack.public_instances
  ssh_private_key  = module.openstack.ssh_private_key
  sudoer_username  = module.openstack.accounts.sudoer.username
}

 output "hostnames" {
   value = module.dns.hostnames
 }
