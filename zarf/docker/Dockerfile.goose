# Build the Go Binary.
FROM golang:1.24.3 AS build_goose
ENV CGO_ENABLED=0

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Build static binary with only PostgreSQL support
RUN go install -tags="no_clickhouse no_mysql no_sqlite3 no_mssql no_ydb no_vertica no_libsql" \
    github.com/pressly/goose/v3/cmd/goose@latest

# Run the Go Binary in Alpine
FROM alpine:3.21.3

RUN addgroup -g 10001 -S goose && \
    adduser -u 10001 -h /migrations -G goose -S goose && \
    apk add --no-cache ca-certificates

WORKDIR /migrations
COPY --from=build_goose --chown=goose:goose /go/bin/goose /bin/goose
COPY --chown=goose:goose api/migrations/ .

USER goose
ENTRYPOINT ["/bin/goose"]
