#!/bin/sh
erlc dht.erl
echo 'l(dht).
R = dht:spawn_ring(10).
dht:insert(R, "the key", "the val").
dht:insert(R, "another key", "another val").
dht:insert(R, "yet another key", "yet another val").
dht:insert(R, "moar key", "moar val").
dht:insert(R, "and a final key", "a final val").
dht:lookup(R, "the key").
dht:lookup(R, "yet another key").
dht:lookup(R, "and a final key").
dht:forward(R, 11, dump).
timer:sleep(1000).' | erl
