#!/bin/bash

SCRIPT_NAME=$1
VM_NAME=$2
VM_USER=${VM_USER:-ubuntu}

orb -m ${VM_NAME} -u root cp -r scripts /
orb -m ${VM_NAME} -u root bash /scripts/${SCRIPT_NAME}
