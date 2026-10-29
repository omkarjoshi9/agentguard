BINARY := agentguard

.PHONY: build run test clean

build:
	go build -o bin/$(BINARY) ./cmd/agentguard

run:
	go run ./cmd/agentguard

test:
	go test ./...

clean:
	rm -rf bin
