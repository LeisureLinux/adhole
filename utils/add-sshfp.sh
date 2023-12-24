#!/bin/sh
# Generate host public key's SSHFP record to run on unbound DNS Server. 
[ ! -z "$1" ] && echo "Syntax: $0 ssh-host" && exit
SSH_HOST=$1
ssh-keygen -r ${SSH_HOST} | sed 's/^/unbound-control local_data /;/ SSHFP . 1 /d;'
