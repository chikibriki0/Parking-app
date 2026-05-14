# Multi-stage build: тонкий runtime-образ без исходников и тулчейна Go.
FROM golang:1.25-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/parking-service ./cmd

FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 app
WORKDIR /app
COPY --from=builder /out/parking-service /app/parking-service
COPY --from=builder /app/frontend /app/frontend

USER app
EXPOSE 8080

CMD ["/app/parking-service"]
