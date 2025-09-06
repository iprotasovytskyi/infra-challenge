# --- Build stage --------------------------------------------------------------
FROM golang:1.22-alpine AS build
WORKDIR /src

# Install build deps (optional but handy)
RUN apk add --no-cache ca-certificates

# Copy sources
# If you have go.mod/go.sum, keep these two lines first for better caching:
# COPY go.mod go.sum ./
# RUN go mod download
COPY . .

# Build static binary
ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go build -trimpath -ldflags="-s -w" -o /out/greeter ./greeter.go

# --- Runtime stage ------------------------------------------------------------
# Distroless = tiny, no shell, runs as nonroot by default
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app

# Copy binary
COPY --from=build /out/greeter /app/greeter

# App listens on 8080
EXPOSE 8080

# Optional default; override in k8s with env
ENV HELLO_TAG=dev

# Run as non-root
USER nonroot
ENTRYPOINT ["/app/greeter"]