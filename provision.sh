#!/bin/bash -xe

VM_NAME=${VM_NAME:-$1}
VM_USER=${VM_USER:-ubuntu}

orb create -a arm64 -u $VM_USER ubuntu:noble ${VM_NAME}
