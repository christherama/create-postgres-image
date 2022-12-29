ARG POSTGRES_VERSION

FROM bitnami/postgresql:${POSTGRES_VERSION}
COPY .data /docker-entrypoint-initdb.d
