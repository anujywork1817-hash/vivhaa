FROM golang:1.25-alpine AS builder

ARG SERVICE=api

WORKDIR /app

RUN apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/service ./cmd/${SERVICE}

FROM alpine:3.20

RUN apk add --no-cache ca-certificates curl

WORKDIR /app

COPY --from=builder /bin/service /app/service

EXPOSE 8080

ENTRYPOINT ["/app/service"]
