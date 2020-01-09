#!/bin/bash

while true; do echo "Script Start";  /opt/HLS_XMLTV/cron.sh; sleep 5m; done &

/usr/local/nginx/sbin/nginx -g "daemon off;"

