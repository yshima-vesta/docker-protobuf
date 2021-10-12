#!/bin/bash -eu

rm -f outputs/*
MYUID=$(id -u) MYGID=$(id -g) docker-compose run --rm $(uname -m)
