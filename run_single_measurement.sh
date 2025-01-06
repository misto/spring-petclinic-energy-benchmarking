#!/bin/bash

source "$HOME/.sdkman/bin/sdkman-init.sh"

APP_HOME="/home/misto/repos/spring-petclinic-rest"

JMETER_CONFIG="/home/misto/repos/spring-petclinic-energy-benchmarking/jmeter-petclinic-server.jmx"

JOULARJX_CONFIG="/home/misto/repos/spring-petclinic-energy-benchmarking/config.properties"

BENCHMARK_DATA="/home/misto/repos/spring-petclinic-energy-benchmarking/benchmark-ddl-and-data.sql"

APP_RUN_IDENTIFIER="$(date +%Y-%m-%d_%H-%M-%S)"
OUTPUT_FOLDER="/home/misto/repos/spring-petclinic-energy-benchmarking/out/$APP_RUN_IDENTIFIER"

JAVA_OPTS="-javaagent:/home/misto/repos/joularjx/target/joularjx-3.0.1.jar -Djoularjx.config=$JOULARJX_CONFIG -Dspring.sql.init.mode=never -Dspring.profiles.active=mysql,jpa -Dserver.servlet.context-path=/ -Dspring.datasource.username=root -Dspring.datasource.password=petclinic"
APP_PORT="9966"
APP_BASE_URL="localhost:$APP_PORT"

# Parse command line arguments
while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
    --spring-boot-version)
    spring_boot_version="${2#*=}"
    shift
    ;;
    --jvm-version)
    jvm_version="${2#*=}"
    shift
    ;;
    --java-version)
    java_version="${2#*=}"
    shift
    ;;
    --webserver)
    webserver="${2#*=}"
    shift
    ;;
    *)
    echo "ERROR: Invalid argument: $1"
    exit 1
    ;;
  esac
  shift
done

if [ -n "$webserver" ] && [[ $spring_boot_version =~ ^2.* ]]; then
  echo "ERROR: Both webserver and Spring Boot 2 cannot be set at the same time."
  exit 1
fi

if [ -z "$spring_boot_version" ]; then
  echo "ERROR: Spring Boot version is required."
  exit 1
fi

if [ -z "$jvm_version" ]; then
  echo "ERROR: JVM version is required."
  exit 1
fi

if [ -z "$java_version" ]; then
  echo "ERROR: Java version (for compilation) is required."
  exit 1
fi

create_output_folders() {
  mkdir -p "$OUTPUT_FOLDER/log"
}

switch_application_branch() {
  echo "+================================+"
  echo "| Switching Application Branch"
  echo "+================================+"

  # Select the branch according to the Spring Boot version
  if [[ $spring_boot_version =~ ^3.* ]]; then
    switch_branch_command="git -C $APP_HOME checkout -f spring-boot-v3.x.x-$webserver"
  elif [[ $spring_boot_version =~ ^2.* ]]; then
    switch_branch_command="git -C $APP_HOME checkout -f spring-boot-v2.x.x"
  else
    echo "ERROR: Spring Boot version must start with 2 or 3."
    return 1
  fi
  
  echo "$switch_branch_command"
  eval "$switch_branch_command"
}

change_spring_boot_version() {
  echo "+================================+"
  echo "| Changing Spring Boot Version"
  echo "+================================+"
  change_spring_boot_version_command="$APP_HOME/mvnw -f $APP_HOME/pom.xml versions:update-parent -DparentVersion=[$spring_boot_version] -DgenerateBackupPoms=false"
  echo "$change_spring_boot_version_command"
  eval "cd $APP_HOME; $change_spring_boot_version_command"
}

change_jvm_version() {
  echo "+================================+"
  echo "| Changing JVM Version"
  echo "+================================+"
  change_jvm_version_command="sdk use java $jvm_version"
  echo "$change_jvm_version_command"
  eval "$change_jvm_version_command"

  verify_jvm_version=$(java -version 2>&1 | awk -F ' ' '/Runtime/ {print $4}')

  # Verify the JVM version:
  if [[ $verify_jvm_version =~ ^$jvm_version* ]]; then
    echo "ERROR: JVM version $jvm_version is not set correctly. Current JVM version is $verify_jvm_version."
    return 1
  fi

}

build_application() {
  echo "+================================+"
  echo "| Building Application"
  echo "+================================+"
  build_output_file="$OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-build.log"

  BUILD_CMD="$APP_HOME/mvnw -f $APP_HOME/pom.xml clean package -Dmaven.test.skip -Dmaven.compiler.release=$java_version"
  
  app_build_command="$BUILD_CMD > $build_output_file 2>&1"
  echo "$app_build_command"

  eval "cd $APP_HOME; $app_build_command"
  if [ $? -ne 0 ]; then
    echo "ERROR: Build failed for application. Check $build_output_file for details."
    return 1
  fi
}

print_app_info() {
  echo "+================================+"
  echo "| Configuration Properties"
  echo "+================================+"
  echo "JVM: $jvm_version"
  echo "Java: $java_version"
  echo "Spring Boot: $spring_boot_version"
  echo "Webserver: $webserver"
  echo "App: $APP_HOME"
  echo "JMeter Config: $JMETER_CONFIG"
  echo "Output Folder: $OUTPUT_FOLDER"
  echo "App Run Identifier: $APP_RUN_IDENTIFIER"
}

check_if_port_is_open() {
  if lsof -Pi :$APP_PORT -sTCP:LISTEN -t >/dev/null; then
    echo "ERROR Port $APP_PORT is already in use. Please stop the application running on this port."
    return 1
  fi
}

start_mysql_container() {
  echo "+================================+"
  echo "| Starting MySQL Container"
  echo "+================================+"
  mysql_container_command="docker run -d --rm -e MYSQL_ROOT_PASSWORD=petclinic -e MYSQL_DATABASE=petclinic -p 3306:3306 mysql:8"
  echo "$mysql_container_command"
  db_container_id=$(eval "$mysql_container_command")
  echo "Container ID: $db_container_id"

  # Wait until the container is ready
  echo "Waiting for MySQL container to start and initialize..."
  until docker exec -it $db_container_id mysql -uroot -ppetclinic -e "SELECT '1';" >/dev/null 2>&1; do
    sleep 1
  done

  # give it a few more seconds to be ready
  sleep 3

  mysql_import_command="docker exec -i $db_container_id mysql -u root -ppetclinic petclinic < $BENCHMARK_DATA"
  echo "$mysql_import_command"
  eval "$mysql_import_command"

  # 2000 is the number of expected pets
  verify_import_command="docker exec -it $db_container_id mysql -u root -ppetclinic -e \"USE petclinic; SELECT count(*) FROM pets;\" | grep 2000"
  echo "$verify_import_command"
  eval "$verify_import_command"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to verify import. Check the MySQL container logs for details."
    return 1
  fi

  echo "MySQL container is ready."
}

start_application() {
  echo "+================================+"
  echo "| Starting Application"
  echo "+================================+"
  run_output_file="$OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-run.log"

  RUN_CMD="java $JAVA_OPTS -jar $APP_HOME/target/*.jar"
  
  app_run_command="$RUN_CMD > $run_output_file 2>&1 &"
  echo "$app_run_command"

  eval "$app_run_command"
  APP_PID=$!

  sleep 2

  if ! ps -p "$APP_PID" > /dev/null; then
    echo "ERROR: Run failed for application. Check $run_output_file for details."
    return 1
  fi
}

check_application_initial_request() {
  timeout=30
  end_time=$((SECONDS + timeout))

  # The application does a redirect on /, so let's wait until we get a 302 response
  while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://$APP_BASE_URL)" != "302" ]]; do
    sleep .00001

    # Check if the timeout has been reached
    if [ $SECONDS -ge $end_time ]; then
      echo "ERROR: Application with PID $APP_PID did not respond within $timeout seconds (timeout)."
      return 1
    fi
  done

  echo "Application with PID $APP_PID successfully started at $(date)."
}

stop_application() {
  echo "+================================+"
  echo "| Stopping Application"
  echo "+================================+"
  app_kill_command="kill -15 $APP_PID && sleep 10"
  echo "$app_kill_command"
  eval "$app_kill_command"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to stop application with PID $APP_PID."
    return 1
  fi
}

stop_mysql_container() {
  echo "+================================+"
  echo "| Stopping MySQL Container"
  echo "+================================+"
  mysql_stop_command="docker stop $db_container_id"
  echo "$mysql_stop_command"
  eval "$mysql_stop_command"
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to stop MySQL container."
    return 1
  fi
}

start_jmeter() {
  echo "+================================+"
  echo "| Starting JMeter"
  echo "+================================+"
  jmeter_output_file="$OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-jmeter.log"

  JMETER_CMD="jmeter -n -t $JMETER_CONFIG -l $OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-jmeter.jtl -j $OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-jmeter.log"
  
  jmeter_command="$JMETER_CMD > $jmeter_output_file 2>&1"
  echo "$jmeter_command"

  eval "$jmeter_command"
  if [ $? -ne 0 ]; then
    echo "ERROR: JMeter run failed. Check $jmeter_output_file for details."
    return 1
  fi
}

save_energy_measurement() {
  echo "+================================+"
  echo "| Saving Energy Measurement"
  echo "+================================+"

  save_energy_measurement_command="find $APP_HOME/joularjx-result -name '*.csv' | xargs -I '{}' mv '{}' $OUTPUT_FOLDER/"
  echo "$save_energy_measurement_command"
  eval "$save_energy_measurement_command"
}

extract_run_properties() {
  echo "+================================+"
  echo "| Extracting Run Properties"
  echo "+================================+"

  # used_jvm_version=$(java -XshowSettings:properties -version 2>&1 | grep "java.runtime.version" | sed -e 's/^[^=]*= *//' -e 's/ *$//')
  # used_jvm_vendor=$(java -XshowSettings:properties -version 2>&1 | grep "java.vendor " | sed -e 's/^[^=]*= *//' -e 's/ *$//')

  echo "JVM: $jvm_version"

  used_java_version=$(javap -verbose $APP_HOME/target/classes/org/springframework/samples/petclinic/PetClinicApplication.class | grep "major version" | awk '{print $3 - 44}')

  echo "Java: $used_java_version"

  spring_versions=($(grep 'Running with' $run_output_file | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/v//'))

  used_spring_boot_version=${spring_versions[0]}
  used_spring_version=${spring_versions[1]}

  # Output the variables to check
  echo "Spring Boot version: $used_spring_boot_version"
  echo "Spring version: $used_spring_version"

  profiles=($(grep 'profiles are active' $run_output_file | grep -oE '"[^"]+"' | sed 's/"//g' | tr '\n' '+' | sed 's/\+$/\n/'))

  echo "Profiles: $profiles"

  joules=($(grep 'Program consumed' $run_output_file | grep -oE '[0-9]+(\.[0-9]+)? joules' | sed 's/ joules//'))

  echo "Joules: $joules"

  jmetertime=$(grep "summary =" "$OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-jmeter.log" | tail -n 1 | awk -F'=' '{print $2}' | sed -E 's/.*in ([0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/')

  echo "JMeter: $jmetertime"

  jmeter_errors=$(grep "summary =" "$OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-jmeter.log" | tail -n 1 | awk -F'Err:' '{gsub(/^[ \t]+/, "", $2); split($2, a, " "); print a[1]}')

  if [ "$jmeter_errors" != "0" ]; then
    echo "ERROR: JMeter run failed with errors. Check $OUTPUT_FOLDER/log/$APP_RUN_IDENTIFIER-jmeter.log for details."
    exit 1
  fi

  results_output_file="$OUTPUT_FOLDER/results.txt"

  > "$results_output_file"
  echo "JVM: $jvm_version" >> "$results_output_file"
  echo "Java: $used_java_version" >> "$results_output_file"
  echo "Spring-Boot: $used_spring_boot_version" >> "$results_output_file"
  echo "Spring: $used_spring_version" >> "$results_output_file"
  echo "Webserver: $webserver" >> "$results_output_file"
  echo "Profiles: $profiles" >> "$results_output_file"
  echo "Joules: $joules" >> "$results_output_file"
  echo "JMeter: $jmetertime" >> "$results_output_file"

  # Extract the energy measurements, excluding some methods that we are not interested in
  find_command="find $OUTPUT_FOLDER/ -name '*filtered-methods-energy.csv' | xargs cat | grep -v 'CGLIB\$STATICHOOK' | grep -v '0.0000' | grep -v 'equals' | grep -v 'invoke' | grep -v 'init' | grep -v 'setCallbacks'| grep -v 'isFrozen' | grep -v 'addAdvisor' | grep -v 'getIndex' | grep -v 'getTargetClass' | sed 's/org.springframework.samples.petclinic.rest.controller.//' | sed 's/,/: /' | sort"
  eval "$find_command >> $results_output_file"

  mv "$OUTPUT_FOLDER" "$OUTPUT_FOLDER-Java-$jvm_version-Spring-Boot-$used_spring_boot_version"
}

cleanup() {
  echo "+================================+"
  echo "| Cleaning up"
  echo "+================================"
  cleanup_command="rm -rf $APP_HOME/joularjx-result"
  echo "$cleanup_command"
  eval "$cleanup_command"
}

create_output_folders

print_app_info

# switch_application_branch || { exit 1; }

change_spring_boot_version || { exit 1; }

change_jvm_version || { exit 1; }

build_application || { exit 1; }

check_if_port_is_open || { exit 1; }

start_mysql_container || { stop_mysql_container && exit 1; }

start_application || { stop_mysql_container && exit 1; }

check_application_initial_request || { stop_mysql_container &&  exit 1; }

start_jmeter || { stop_application && stop_mysql_container && exit 1; }

stop_application || { stop_mysql_container && exit 1; }

stop_mysql_container || { exit 1; }

save_energy_measurement || { exit 1; }

extract_run_properties || { exit 1; }

cleanup || { exit 1; }
