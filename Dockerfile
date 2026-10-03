FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /workspace
COPY pom.xml .
COPY src ./src
RUN mvn --batch-mode -DskipTests package \
    && cp target/signaling-service-1.0.0.jar /app.jar

FROM eclipse-temurin:25-jre-alpine
WORKDIR /app
COPY --from=build --chown=10001:10001 /app.jar app.jar
USER 10001:10001
EXPOSE 8083
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-Xms64m", "-Xmx128m", "-Xss256k", "-XX:MaxMetaspaceSize=96m", "-XX:ReservedCodeCacheSize=32m", "-XX:+UseSerialGC", "-jar", "/app/app.jar"]
