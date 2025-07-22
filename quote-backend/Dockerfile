FROM public.ecr.aws/docker/library/golang:1.20-alpine:latest

WORKDIR /app
COPY quote-server.go .

RUN go build -o qotm quote-server.go
EXPOSE 8080

CMD ["./qotm"]