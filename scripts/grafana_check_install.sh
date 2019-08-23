#!/bin/bash

#set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

DASHBOARD_UID=eXPEaNnZz
: "${GRAFANA_URL:=http://localhost:3000}"
: "${DASHBOARD_DEFN:=${DIR}/../config/grafana/istio.json}"

echo "      GRAFANA_URL=$GRAFANA_URL"
echo "    DASHBOARD_UID=$DASHBOARD_UID"
echo "   DASHBOARD_DEFN=$DASHBOARD_DEFN"

status=$(curl -Is --header 'Accept: application/json' $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID 2>/dev/null | head -n 1 | cut -d$' ' -f2)
if [[ "$status" == "200" ]]; then
  echo "Canary Dashboard already defined in $GRAFANA_URL"
  #DASHBOARD_VERSION=$( curl -s --header 'Accept: application/json' \
  #  $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID \
  #| jq '.dashboard.version')
  #DASHBOARD_ID=$( curl -s --header 'Accept: application/json' \
  #  $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID \
  #| jq '.dashboard.id')
  #echo "DASHBOARD_VERSION=$DASHBOARD_VERSION"
  #echo "     DASHBOARD_ID=$DASHBOARD_ID"
  #echo "{ \"meta\": $(curl -s --header 'Accept: application/json' $GRAFANA_URL/api/dashboards/uid/$DASHBOARD_UID | jq '.meta'), \"dashboard\": $(cat $DASHBOARD_DEFN) }" \
  #| jq --argjson VERSION $DASHBOARD_VERSION --argjson ID $DASHBOARD_ID \
  #    '.dashboard.id = $ID | .dashbord.version = $VERSION' \
  #| curl --request POST \
  #  --header 'Accept: application/json' \
  #  --header 'Content-Type: application/json' \
  #  $GRAFANA_URL/api/dashboards/db \
  #  --data @-
else
  echo "Defining canary dashboard on $GRAFANA_URL"
  echo "{ \"dashboard\": $(cat $DASHBOARD_DEFN) }" \
  | jq 'del(.dashboard.id) | del(.dashboard.version)' \
  | curl --request POST \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    $GRAFANA_URL/api/dashboards/db \
    --data @-
fi
