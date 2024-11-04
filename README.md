# Spring Petclinic Energy Testing

See the blog post []() for more information about this repository.

## Running the tests

To run the tests, you can use the `run_single_measurement.sh` script. This script will run the tests for a specific Spring Boot version, JVM version, Java version, and web server. For example, to run the tests for Spring Boot 3.3.1, JVM 21.0.4-tem, Java 21, and Tomcat, you can run the following command:

```
./run_single_measurement.sh --spring-boot-version 3.3.1 --jvm-version 21.0.4-tem --java-version 21 --webserver tomcat
```

Note that not all combinations of Spring Boot versions, JVM versions, Java versions, and web servers are supported.