#!/bin/bash

FRENETIC=~/src/frenetic/frenetic.native

$FRENETIC http-controller &
FPID=$!
sleep 1

python $@ &
PPID=$!
sleep 1

sudo mn --controller=remote  --topo=single,2 --mac --arp
sleep 1

ps -auwwx | grep "python $@" |awk '{print $2}' | xargs kill
kill $PPID
kill $FPID
