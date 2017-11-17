stage('Build') {
  if (!dockerImageExists("kuma-integration-tests:${GIT_COMMIT_SHORT}")) {
    dockerImageBuild("kuma-integration-tests:${GIT_COMMIT_SHORT}",
                     ["pull": true,
                      "dockerfile": config.job.dockerfile])
  }
}

def functional_test(browser, selenium_name, test_name, base_dir) {
  return {
    node {
      def cmd = "py.test tests/functional" +
                " --driver Remote" +
                " --capability browserName ${browser}" +
                " --host hub" +
                " --base-url='${config.job.base_url}'" +
                " --junit-xml=/test_results/functional-${browser}.xml"
      if (config.job && config.job.tests) {
        cmd += " -m \"${config.job.tests}\""
      }
      if (config.job && config.job.maintenance_mode) {
        cmd += " --maintenance-mode"
      }
      def browser_env = ""
      if (browser == 'firefox') {
        browser_env = "--shm-size 2g"
      }
      if (browser == 'chrome') {
        browser_env = "-v /dev/shm:/dev/shm"
      }

      dockerRun("selenium/standalone-${browser}:${config.job.selenium}",
                ["docker_args": "--name ${selenium_name} ${browser_env}"]) {
        dockerRun("kuma-integration-tests:${GIT_COMMIT_SHORT}",
                  ["docker_args": "--link ${selenium_name}:hub" +
                                  " --name ${test_name}" +
                                  " --volume ${base_dir}/test_results:/test_results" +
                                  " --user 1000",
                   "cmd": cmd])
      }
    }
  }
}

def headless_test(test_name, base_dir) {
  return {
    node {
      dockerRun("kuma-integration-tests:${GIT_COMMIT_SHORT}",
                  ["docker_args": "--volume ${base_dir}/test_results:/test_results" +
                                  " --name ${test_name}" +
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
    def chrome_selenium = "kuma-selenium-chrome-${BUILD_TAG}"
    def chrome_tests = "kuma-tests-chrome-${BUILD_TAG}"
    def firefox_selenium = "selenium-firefox-${BUILD_TAG}"
    def firefox_tests = "kuma-tests-firefox-${BUILD_TAG}"
    def headless_tests = "kuma-test-headless-${BUILD_TAG}"
    allTests['chrome'] = functional_test('chrome', chrome_selenium, chrome_tests, base_dir)
    allTests['firefox'] = functional_test('firefox', firefox_selenium, firefox_tests, base_dir)
    allTests['headless'] = headless_test(headless_tests, base_dir)
    parallel allTests
}
