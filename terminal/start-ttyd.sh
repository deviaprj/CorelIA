#!/bin/sh
exec ttyd -p 7681 -c "${TTYD_USER}:${TTYD_PASS}" su - corelia
