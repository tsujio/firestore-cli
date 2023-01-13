package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"

	"cloud.google.com/go/firestore"
	"github.com/tsujio/firestore-cli/queries"
	"google.golang.org/api/iterator"
)

func doQuery(cli *firestore.Client, query string) error {
	evalValueExpr := func(expr interface{}) (interface{}, error) {
		switch e := expr.(type) {
		case queries.StringExpr:
			return e.Literal[1 : len(e.Literal)-1], nil
		case queries.IntegerExpr:
			return strconv.Atoi(e.Literal)
		default:
			return nil, fmt.Errorf("Invalid expr type: %T", e)
		}
	}

	queryAST, err := queries.Parse(strings.NewReader(query))
	if err != nil {
		return err
	}

	collection := queryAST.Collection.Name.Literal

	col := cli.Collection(collection)
	if col == nil {
		return fmt.Errorf("Invalid collection: %s", collection)
	}

	q := col.Query
	for _, option := range queryAST.Options {
		switch opt := option.(type) {
		case queries.WhereOption:
			var op string
			switch opt.Comparator {
			case queries.ComparatorEq:
				op = "=="
			default:
				return fmt.Errorf("Invalid comparator")
			}
			value, err := evalValueExpr(opt.Value)
			if err != nil {
				return err
			}
			q = q.Where(opt.Field.Literal, op, value)
		case queries.OrderByOption:
			dir := firestore.Asc
			if opt.DirectionDesc {
				dir = firestore.Desc
			}
			q = q.OrderBy(opt.Field.Literal, dir)
		case queries.LimitOption:
			value, err := evalValueExpr(opt.Limit)
			if err != nil {
				return err
			}
			q = q.Limit(value.(int))
		default:
			return fmt.Errorf("Invalid option: %T", opt)
		}
	}

	iter := q.Documents(context.Background())

	data := []map[string]interface{}{}

	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		data = append(data, doc.Data())
	}

	output := map[string]interface{}{
		"data": data,
	}

	return json.NewEncoder(os.Stdout).Encode(output)
}

func main() {
	project := flag.String("project", "", "GCP project")

	flag.Parse()

	args := flag.Args()

	queryCmd := flag.NewFlagSet("query", flag.ExitOnError)

	cli, err := firestore.NewClient(context.Background(), *project)
	if err != nil {
		fmt.Fprintf(os.Stderr, "%+v", err)
		os.Exit(1)
	}
	defer cli.Close()

	switch args[0] {
	case queryCmd.Name():
		if err := queryCmd.Parse(args[1:]); err != nil {
			fmt.Fprintf(os.Stderr, "%+v", err)
			os.Exit(1)
		}
		cmdArgs := queryCmd.Args()
		if err := doQuery(cli, cmdArgs[0]); err != nil {
			fmt.Fprintf(os.Stderr, "%+v", err)
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "Unknown command\n")
		os.Exit(1)
	}
}
