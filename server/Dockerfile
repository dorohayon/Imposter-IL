# Static binary, distroless runtime: nothing in the image to exploit and
# nothing to patch on a schedule.
FROM golang:1.26-alpine AS build
WORKDIR /src
# Only go.mod and go.sum first, so the dependency layer is cached.
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
EXPOSE 8080
# Caddy terminates TLS and is the only thing that talks to this port, so the
# server trusts X-Forwarded-For. Metrics stay on loopback.
ENV PORT=8080 TRUST_PROXY=1 METRICS_ADDR=127.0.0.1:9090
USER nonroot:nonroot
ENTRYPOINT ["/server"]
