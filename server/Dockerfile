# Build the Spring Boot server jar, then run it on a slim JRE.
FROM gradle:8.10-jdk17 AS build
WORKDIR /src
COPY . .
RUN gradle :server:bootJar --no-daemon

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /src/server/build/libs/*.jar /app/server.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/server.jar"]
