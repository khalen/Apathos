#!/bin/sh

# Iterate on the kernel. Does "make" then sends a ctrl-R to the default USB serial port.
make
./rebootpi.sh

