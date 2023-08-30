#!/bin/bash

(
    rm -rf /tmp/hvetsa/image
    git clone https://github.com/hvetsa/image /tmp/hvetsa/image
    docker build -t hvetsa:latest -f /tmp/hvetsa/image/image/Dockerfile /tmp/hvetsa/image 
)