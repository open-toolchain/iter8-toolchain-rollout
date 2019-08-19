#!/bin/bash

#set -x

DASHBOARD_UID=eXPEaNnZz

echo "      GRAFANA_URL=$GRAFANA_URL"
echo "    DASHBOARD_UID=$DASHBOARD_UID"
echo "   DASHBOARD_DEFN=$DASHBOARD_DEFN"

# default version
DASHBOARD_VERSION=1

status=$(curl -Is --header 'Accept: application/json' $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID 2>/dev/null | head -n 1 | cut -d$' ' -f2)
if [[ "$status" == "200" ]]; then
  DASHBOARD_VERSION=$( curl -s --header 'Accept: application/json' \
    $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID \
  | jq '.dashboard.version' \
  )
fi

echo "DASHBOARD_VERSION=$DASHBOARD_VERSION"

#curl -s --header 'Accept: application/json' \
#  $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID \
#| jq '.' > iter8-current.json
#echo "{ \"meta\": $(curl -s --header 'Accept: application/json' $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID | jq '.meta'), \"dashboard\": $(cat $DASHBOARD_DEFN) }" | jq --argjson VERSION $DASHBOARD_VERSION '.dashboard.version = $VERSION' > iter8-new.json
#diff -w iter8-current.json iter8-new.json > diff

echo "{ \"meta\": $(curl -s --header 'Accept: application/json' $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID | jq '.meta'), \"dashboard\": $(cat $DASHBOARD_DEFN) }" | jq --argjson VERSION $DASHBOARD_VERSION '.dashboard.version = $VERSION' \
| curl --request POST \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  http://169.46.107.203:31769/api/dashboards/db \
  --data @-
