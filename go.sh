#!/bin/sh
rdmd gendeps.d checked
rdmd -debug -I.. go.d $@
