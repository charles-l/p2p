#!/bin/sh
erlc chord.erl
echo 'l(chord).
R = chord:spawn_ring(10).
chord:insert(R, "the key", "the val").
chord:insert(R, "another key", "another val").
chord:insert(R, "yet another key", "yet another val").
chord:insert(R, "moar key", "moar val").
chord:insert(R, "and a final key", "a final val").
chord:lookup(R, "the key").
chord:lookup(R, "yet another key").
chord:lookup(R, "and a final key").
chord:forward(R, 11, dump).
timer:sleep(1000).' | erl
