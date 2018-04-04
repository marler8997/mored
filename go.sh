#!/bin/sh
rund gendeps.d checked
rund -debug -I.. go.d $@
