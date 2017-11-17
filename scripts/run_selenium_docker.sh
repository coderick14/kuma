#!/bin/bash -vx
PYTEST_ARGS="${@}"
if [ -z "$PYTEST_ARGS" ]; then
    PYTEST_ARGS="tests/functional -m \"not login\" -vv"
fi
echo "ARGS=$PYTEST_ARGS"
BASE_URL=${BASE_URL:-https://stage.mdn.moz.works}
NAME_SUFFIX=${NAME_SUFFIX:-kuma}
SELENIUM_TAG=${SELENIUM_TAG:-3.7.1-argon}
BROWSERS=${BROWSERS:-chrome firefox}
SELENIUM_LOGS=${SELENIUM_LOGS:-0}
PAUSE=${PAUSE:-0}
TRACE_GECKODRIVER=${TRACE_GECKODRIVER:-0}
FIREFOX_ENV=${FIREFOX_ENV:- --shm-size 2g}
CHROME_ENV=${CHROME_ENV:- -v /dev/shm:/dev/shm}
if [ "$TRACE_GECKODRIVER" != 0 ]; then
    FIREFOX_ENV="$FIREFOX_ENV --env DRIVER_LOGLEVEL=trace"
fi

find . \( -name \*.pyc -o -name \*.pyo -o -name __pycache__ \) -prune -exec rm -rf {} +

(
  set -e
  docker build -t kuma-integration-tests:latest --pull=true -f docker/images/integration-tests/Dockerfile .

  IFS=" "
  for browser in ${BROWSERS}; do
    if [[ "$browser" == "firefox" ]]; then
        BROWSER_ENV=$FIREFOX_ENV
    elif [[ "$browser" == "chrome" ]]; then
        BROWSER_ENV=$CHROME_ENV
    else
        BROWSER_ENV=
    fi
    docker run -d --name "selenium-${browser}-${NAME_SUFFIX}" ${BROWSER_ENV} "selenium/standalone-${browser}:${SELENIUM_TAG}"
    if [[ "$browser" == "firefox" ]]; then
        docker exec "selenium-${browser}-${NAME_SUFFIX}" /opt/bin/generate_config
    fi
  done
  for browser in ${BROWSERS}; do
    cmd="pytest --driver Remote --capability browserName ${browser} --host browser --base-url=${BASE_URL} ${PYTEST_ARGS}"
    docker run --link "selenium-${browser}-${NAME_SUFFIX}:browser" kuma-integration-tests:latest sh -c "$cmd"
  done
)

if [[ "$SELENIUM_LOGS" != "0" ]]; then
  for browser in ${BROWSERS}; do
    docker logs "selenium-${browser}-${NAME_SUFFIX}"
  done
fi

if [[ "$PAUSE" != "0" ]]; then
    read -p "Pausing. To remove selenium images, press [ENTER]: "
fi

for browser in ${BROWSERS}; do
  docker stop "selenium-${browser}-${NAME_SUFFIX}"
  docker rm --volumes "selenium-${browser}-${NAME_SUFFIX}"
done
