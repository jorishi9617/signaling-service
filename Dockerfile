FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /workspace
RUN apt-get update && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch master https://github.com/jorishi9617/common-library.git common-library
RUN mvn --batch-mode -f common-library/pom.xml -DskipTests install
COPY pom.xml signaling-service/pom.xml
COPY src signaling-service/src
RUN mvn --batch-mode -f signaling-service/pom.xml -DskipTests package \
    && cp signaling-service/target/signaling-service-1.0.0.jar /app.jar

FROM eclipse-temurin:25-jre
WORKDIR /app
COPY --from=build --chown=10001:10001 /app.jar app.jar
USER 10001:10001
EXPOSE 8083
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
