#! /bin/bash

./three.sh &
for k in {1..60}; do
    echo "two: $$ $k"
    sleep 10
done
exit 0
