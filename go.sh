#!/usr/bin/env bash
set -e
rund -g -debug gendeps.d checked
rund -debug -g go.d $@
