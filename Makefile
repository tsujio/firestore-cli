.PHONY: all

all: main.go parser.go
	go build -o firestore-cli

parser.go: queries/parser.go.y
	goyacc -o queries/parser.go queries/parser.go.y
