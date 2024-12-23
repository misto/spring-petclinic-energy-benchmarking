#!/bin/bash


# Spring versions: https://mvnrepository.com/artifact/org.springframework.boot/spring-boot-starter-parent


# java_sdk_versions=( "17.0.12-tem" "21.0.4-tem" "22.0.2-tem")
java_sdk_versions=( "17.0.12-tem" "21.0.4-tem" "22.0.2-tem" )


# spring_boot_versions=("3.0.0" "3.0.1" "3.0.2" "3.0.3" "3.0.4" "3.0.5" "3.0.6" "3.0.7" "3.0.8" "3.0.9" "3.0.10" "3.0.11" "3.0.12" "3.0.13")

# "2.7.18" "3.0.13" "3.1.12" "3.2.8" "3.3.2" "3.4.0"

spring_boot_versions=( "3.4.1" )

webservers=( "tomcat" )  # "undertow" "jetty"

cleanup() {
    echo "Stopping caffeinate..."
    kill $CAFFEINATE_PID
}

# Start caffeinate to prevent the computer from going to sleep
caffeinate -d &
CAFFEINATE_PID=$!
trap cleanup EXIT

for java_sdk_version in "${java_sdk_versions[@]}"
do
    for spring_boot_version in "${spring_boot_versions[@]}"
    do
        for webserver in "${webservers[@]}"
        do
            for i in {1..5}
            do 
                ./run_single_measurement.sh \
                --spring-boot-version $spring_boot_version \
                --jvm-version $java_sdk_version \
                --java-version 21 \
                --virtual-threads false \
                --webserver $webserver || { exit 1; }
            done
        done
    done
done
