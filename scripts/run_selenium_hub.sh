#!/bin/bash -vx
PYTEST_ARGS="${@}"
if [ -z "$PYTEST_ARGS" ]; then
    PYTEST_ARGS="tests/functional -m \"not login\" -vv -sx"
fi
echo "ARGS=$PYTEST_ARGS"
BASE_URL=${BASE_URL:-https://stage.mdn.moz.works}
NAME_SUFFIX=${NAME_SUFFIX:-kuma}
SELENIUM_TAG=${SELENIUM_TAG:-3.7.1-argon}
BROWSERS=${BROWSERS:-chrome firefox}
SELENIUM_LOGS=${SELENIUM_LOGS:-0}
PAUSE=${PAUSE:-0}
TRACE_GECKODRIVER=${TRACE_GECKODRIVER:-0}
FF_ENV=${FF_ENV:- --shm-size 2g}
if [ "$TRACE_GECKODRIVER" != 0 ]; then
    FF_ENV="$FF_ENV --env DRIVER_LOGLEVEL=trace"
fi

find . \( -name \*.pyc -o -name \*.pyo -o -name __pycache__ \) -prune -exec rm -rf {} +

(
  set -e
  docker build -t kuma-integration-tests:latest --pull=true -f docker/images/integration-tests/Dockerfile .
  docker run -d --name "selenium-hub-${NAME_SUFFIX}" -p 4444:4444 "selenium/hub:${SELENIUM_TAG}"

  IFS=" "
  for browser in ${BROWSERS}; do
    if [[ "$browser" == "firefox" ]]; then
        BROWSER_ENV=$FF_ENV
    else
        BROWSER_ENV=
    fi
    docker run -d --name "selenium-node-${browser}-${NAME_SUFFIX}" --link selenium-hub-kuma:hub ${BROWSER_ENV} "selenium/node-${browser}:${SELENIUM_TAG}"
    if [[ "$browser" == "firefox" ]]; then
        docker exec "selenium-node-${browser}-${NAME_SUFFIX}" /opt/bin/generate_config
    fi
  done
  for browser in ${BROWSERS}; do
    cmd="pytest --driver Remote --capability browserName ${browser} --host hub --base-url=${BASE_URL} ${PYTEST_ARGS}"
    docker run --link "selenium-hub-${NAME_SUFFIX}:hub" kuma-integration-tests:latest sh -c "$cmd"
  done
)

if [[ "$SELENIUM_LOGS" != "0" ]]; then
  docker logs "selenium-hub-${NAME_SUFFIX}"
  for browser in ${BROWSERS}; do
    docker logs "selenium-node-${browser}-${NAME_SUFFIX}"
  done
fi

if [[ "$PAUSE" != "0" ]]; then
    read -p "Pausing. To remove hub/node images, press [ENTER]: "
fi

for browser in ${BROWSERS}; do
  docker stop "selenium-node-${browser}-${NAME_SUFFIX}"
  docker rm --volumes "selenium-node-${browser}-${NAME_SUFFIX}"
done
docker stop "selenium-hub-${NAME_SUFFIX}"
docker rm --volumes "selenium-hub-${NAME_SUFFIX}"
