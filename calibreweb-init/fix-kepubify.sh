#!/bin/sh

while [ ! -f /usr/bin/kepubify ]; do
    sleep 1
done

chmod +x /usr/bin/kepubify