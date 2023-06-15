#!/bin/env python3 
from base64 import b64encode
from os import environ
from json import dumps, loads
from os.path import exists, join
from sys import stderr, stdout
from string import Template
from urllib.request import urlopen

PREFIX = "AZURE_"

def slurp(filename, as_template=True):
    # Make sure we only replace variables that start with COMPUTE_
    TEMPLATE_VALUES = {k: v for k, v in environ.items() if k.startswith(PREFIX)}

    with open(f"cloud-config/{filename}", "r") as config:
        if as_template:
            # parse a YAML file and replace ${VALUE}s (and $VALUEs) 
            buffer = Template(config.read()).safe_substitute(TEMPLATE_VALUES)
        else:
            buffer = config.read()
        # Save a copy of the generated file for debugging
        with open(f"parameters/{filename}", "w") as debug:
            debug.write(buffer)
    return b64encode(bytes(buffer, 'utf-8')).decode()

ADMIN_USERNAME = environ[f'{PREFIX}ADMIN_USERNAME']
OWN_PUBKEY = join(environ['HOME'],'.ssh','id_rsa.pub')
GEN_PUBKEY = 'keys/' + ADMIN_USERNAME + '.pub'

if (environ.get('OWN_KEY','false').lower() == 'true') and exists(OWN_PUBKEY):
    admin_public_key = open(OWN_PUBKEY,'r').read()
    stderr.write('Warning: using %s instead of freshly generated keys.\n' % OWN_PUBKEY)
elif exists(GEN_PUBKEY):
    admin_public_key = open(GEN_PUBKEY,'r').read()
else:
    stderr.write('No public keys found, exiting.\n')
    exit(1)

# Figure out our public IP address and apply an ACL
if (environ.get('APPLY_ORIGIN_NSG','false').lower() == 'true'):
    allowed_management_ips = []
    res = loads(urlopen('https://ipinfo.io/json').read().decode('utf-8'))
    ip = res['ip']
    stderr.write('Your public IP is ' + ip + '. Applying NSG to SSH.\n')
    allowed_management_ips.append(ip)
else:
    allowed_management_ips = ["*"]

# Retrieve the list of Cloudflare proxies and apply an ACL so the ingress only accepts traffic from those
if (environ.get('APPLY_CLOUDFLARE_NSG','false').lower() == 'true'):
    allowed_ingress_ips = allowed_management_ips
    cf = loads(urlopen('https://api.cloudflare.com/client/v4/ips').read().decode("utf-8"))
    if cf['success'] is True:
        stderr.write('Adding Cloudflare CIDRs to HTTP(S) NSG.\n')
        for i in cf['result']['ipv4_cidrs']:
            allowed_ingress_ips.append(i)
        # IPv6 cannot currently be specified in the same rule, so we're leaving it out for now
        #for i in cf['result']['ipv6_cidrs']:
        #    allowed_ingress_ips.append(i)
        # allow access from controlling machine
        res = loads(urlopen('https://ipinfo.io/json').read().decode('utf-8'))
        ip = res['ip']
        stderr.write('Your public IP is ' + ip + '. Adding to HTTP(S) NSG.\n')
    else:
        stderr.write('Could not retrieve Cloudflare CIDRs, exiting.\n')
        exit(1)
else:
    allowed_ingress_ips = allowed_management_ips

if (environ.get(f'{PREFIX}TAILSCALE_AUTHKEY','false').lower() == 'false'):
    stderr.write(f'Warning: no Tailscale authkey specified in {PREFIX}TAILSCALE_AUTHKEY, exiting.\n')
    exit(1)

params = {
    "adminUsername": {
        "value": ADMIN_USERNAME
    },
    "adminPublicKey": {
        "value": admin_public_key
    },
    "instanceSSHPort": { 
        "value": int(environ.get(f'{PREFIX}SSH_PORT', 22))
    },
    "instanceManagementAllowedSourceAddressPrefixes": { 
        "value": allowed_management_ips
    },
    "instanceCustomData": {
        # cloud-init.yaml is a template that is filled in with environment variables
        "value": slurp("cloud-init.yaml") 
    },
    "instanceSize": {
        "value": environ.get(f'{PREFIX}SKU', 'Standard_B4ms').strip()
    },
    "diskSizeGB": {
        "value": int(environ.get(f'{PREFIX}DISK_SIZE', 128)) 
    },
    "instancePrefix": {
        "value": environ.get(f'{PREFIX}INSTANCE', 'ubuntu').strip()
    },
    "instanceArchitecture": {
        "value": environ.get(f'{PREFIX}ARCHITECTURE', 'x86_64').strip()
    },
    "instancePriority": {
        "value": environ.get(f'{PREFIX}PRIORITY', 'Regular').strip()
    },
    "diskType": {
        "value": environ.get(f'{PREFIX}STORAGE', 'Standard_LRS').strip()
    }
}

stderr.write('Using SKUs: %s (%s)\n' % (params['instanceSize']['value'],  params['instancePriority']['value']))

stdout.write(dumps(params, indent=4))