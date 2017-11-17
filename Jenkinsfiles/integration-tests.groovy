stage('Build') {
  if (!dockerImageExists("kuma-integration-tests:${GIT_COMMIT_SHORT}")) {
    dockerImageBuild("kuma-integration-tests:${GIT_COMMIT_SHORT}",
                     ["pull": true,
                      "dockerfile": config.job.dockerfile])
  }
}


def functional_test(browser, base_dir) {
  return {
    node {
      def cmd = "py.test tests/functional" +
                " --driver Remote" +
                " --capability browserName ${browser}" +
                " --host hub" +
                " --base-url='${config.job.base_url}'" +
                " --junit-xml=/test_results/functional-${browser}.xml"
      def hubname = "selenium-hub-for-${browser}-${BUILD_TAG}"
      if (config.job && config.job.tests) {
        cmd += " -m \"${config.job.tests}\""
      }
      if (config.job && config.job.maintenance_mode) {
        cmd += " --maintenance-mode"
      }
      dockerRun("selenium/hub:${config.job.selenium}",
                ["docker_args": "--name ${hubname}"]) {
        dockerRun("selenium/node-${browser}:${config.job.selenium}",
                  ["docker_args": "--link ${hubname}:hub",
                   "copies": config.job.selenium_nodes]) {
          dockerRun("kuma-integration-tests:${GIT_COMMIT_SHORT}",
                    ["docker_args": "--link ${hubname}:hub" +
                                    " --volume ${base_dir}/test_results:/test_results" +
                                    " --user 1000",
                     "cmd": cmd])
        }
      }
    }
  }
}

def headless_test(base_dir) {
  return {
    node {
      dockerRun("kuma-integration-tests:${GIT_COMMIT_SHORT}",
                  ["docker_args": "--volume ${base_dir}/test_results:/test_results" +
                                  " --user 1000",
                  "cmd": "py.test tests/headless" +
                          " --base-url='${config.job.base_url}'" +
                          " --junit-xml=/test_results/headless.xml"])
    }
  }
}

stage('Test') {
    def allTests = [:]
    def base_dir = pwd()
    allTests['chrome'] = functional_test('chrome', base_dir)
    allTests['firefox'] = functional_test('firefox', base_dir)
    allTests['headless'] = headless_test(base_dir)
    parallel allTests
}
