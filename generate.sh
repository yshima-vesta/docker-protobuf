#!/bin/bash -eu

MYUID=$(id -u) MYGID=$(id -g) docker-compose run --rm $(uname -m)
