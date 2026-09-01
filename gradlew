#!/bin/sh
if [ ! -f ./gradle/wrapper/gradle-wrapper.jar ]; then
    gradle wrapper --gradle-version 8.2
fi
./gradlew "$@"
