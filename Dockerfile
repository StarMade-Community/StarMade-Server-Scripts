ARG JAVA_VERSION=21
FROM eclipse-temurin:${JAVA_VERSION}-jre-jammy

WORKDIR /starmade

ENV JVM_MIN_HEAP=4g
ENV JVM_MAX_HEAP=16g
ENV JVM_EXTRA_ARGS=""

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# StarMade default game port (TCP + UDP)
EXPOSE 4242/tcp 4242/udp

ENTRYPOINT ["docker-entrypoint.sh"]
