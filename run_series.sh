#!/bin/bash

# Spring versions: https://mvnrepository.com/artifact/org.springframework.boot/spring-boot-starter-parent

java_sdk_versions=("8.0.432-tem" "11.0.25-tem" "17.0.13-tem" "21.0.5-tem")

# java_sdk_versions=("8.0.432-tem" "11.0.25-tem" "17.0.13-tem" "21.0.5-tem")
# java_sdk_versions=("17.0.13-tem" "21.0.5-tem")
java_sdk_versions=("23.0.1-tem")

# spring_boot_versions=("3.0.13" "3.1.12" "3.2.12" "3.3.7" "3.4.1")
spring_boot_versions=("3.4.1")

webservers=( "tomcat" )  # "undertow" "jetty"

for java_sdk_version in "${java_sdk_versions[@]}"
do
    java_version=$(echo "$java_sdk_version" | cut -d'.' -f1)
    
    for spring_boot_version in "${spring_boot_versions[@]}"
    do
        for webserver in "${webservers[@]}"
        do
            for i in {1..10}
            do 
                ./run_single_measurement.sh \
                --spring-boot-version $spring_boot_version \
                --jvm-version $java_sdk_version \
                --java-version "$java_version" \
                --virtual-threads "false" \
                --webserver $webserver || { exit 1; }
            done
        done
    done
done
