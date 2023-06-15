# azure-dev-bootstrap

A quick hack to run an Azure Development Instance with a few tools pre-installed and accessible via TailScale.

## What

This is an Azure Resource Manager template that automatically deploys a development instance running Ubuntu 22.04 and a small set of development tools, namely `pyenv`, `nodenv`, Go and Docker CE.

The template defaults to deploying a `Standard_B4ms` VM with a relatively large Premium SSD disk size (P10, 128GB). It also deploys (and mounts) an Azure File Share on the machine with (very) permissive access at `/srv`, which makes it quite easy to keep copies of your work between VM instantiations.

## Why

I needed a baseline template for remote development sandboxes, and I wanted it done purely through the CLI with reproducible results.

## Roadmap

* [x] Make `Makefile` self-documenting
* [x] Automatically set up Tailscale with `--authkey` to remove need for open SSH port in NSG
* [x] tweak some defaults
* [x] remove unused packages from `cloud-config`
* [x] tweak `Makefile`
* [x] remove unnecessary files from repo and trim history
* [x] fork from [`azure-stable-diffusion`][asd], new `README`

## `Makefile` commands

* `make help` - shows a list of available commands
* `make keys` - generates an SSH key for provisioning
* `make deploy-storage` - deploys shared storage
* `make params` - generates ARM template parameters
* `make deploy-compute` - deploys VM
* `make view-deployment` - view deployment status
* `make watch-deployment` - watch deployment progress
* `make ssh` - opens an SSH session to the instance and sets up TCP forwarding to `localhost`
* `make tail-cloud-init` - opens an SSH session and tails the `cloud-init` log
* `make list-endpoints` - list DNS aliases
* `make destroy-environment` - destroys the entire environment (should not be the default)
* `make destroy-compute` - destroys only the compute resources (should be the default if you want to save costs)
* `make destroy-storage` - destroys the storage (should be avoided)

## Recommended Sequence

```bash
az login
make keys
make deploy-storage
TAILSCALE_AUTHKEY=<your auth key> make params
make deploy-compute
make view-deployment
# Go to the Azure portal and check the deployment progress

# Clean up after we're done working for the day, to save costs (preserves storage)
make destroy-compute

# Clean up the whole thing (destroys storage as well)
make destroy-environment
```

## Requirements

[Azure Cloud Shell](https://shell.azure.com/) (which includes all the below in `bash` mode) or:

* [Python 3][p]
* The [Azure CLI][az] (`pip install -U -r requirements.txt` will install it)
* GNU `make` (you can just read through the `Makefile` and type the commands yourself)

## Deployment Notes

> **Pro Tip:** You can set `STORAGE_ACCOUNT_GROUP` and `STORAGE_ACCOUNT_NAME` inside an `.env` file if you want to use a pre-existing storage account. As long as you use `make` to do everything, the value will be automatically overridden.

## Disclaimers

Keep in mind that this is not meant to be used as a production service.

[asd]: https://github.com/rcarmo/azure-stable-diffusion/
[p]: http://python.org
[az]: https://github.com/Azure/azure-cli