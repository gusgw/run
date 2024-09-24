#! /bin/bash

./two.sh &
for k in {1..60}; do
    echo "one: $$ $k"
    sleep 10
done
exit 0
