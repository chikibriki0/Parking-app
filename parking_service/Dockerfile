FROM golang:1.25-alpine

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go build -o parking-service ./cmd

EXPOSE 8080

CMD ["./parking-service"]