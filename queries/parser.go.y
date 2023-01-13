%{
package queries

import (
    "errors"
    "io"
    "text/scanner"
)

type lexToken struct {
    token   int
    literal string
}

type Query struct {
    Collection Collection
    Options    []interface{}
}

type Collection struct {
    Name IdentExpr
}

type WhereOption struct {
    Field      IdentExpr
    Comparator Comparator
    Value      interface{}
}

type OrderByOption struct {
    Field         IdentExpr
    DirectionDesc bool
}

type LimitOption struct {
    Limit IntegerExpr
}

type Comparator int

const (
    ComparatorEq Comparator = iota
)

type IdentExpr struct {
    Literal string
}

type StringExpr struct {
    Literal string
}

type IntegerExpr struct {
    Literal string
}

%}

%union{
    expr  interface{}
    token lexToken
}

%type<expr> query
%type<expr> collection
%type<expr> options
%type<expr> option
%type<expr> comparator
%type<expr> direction
%type<expr> value
%token<token> WHERE
%token<token> ORDERBY
%token<token> LIMIT
%token<token> IDENT
%token<token> EQ
%token<token> ASC
%token<token> DESC
%token<token> STRING
%token<token> INT

%%

query
    : collection options
    {
        $$ = Query{Collection: $1.(Collection), Options: $2.([]interface{})}
        yylex.(*lexer).result = $$.(Query)
    }

collection
    : IDENT
    {
        $$ = Collection{Name: IdentExpr{Literal: $1.literal}}
    }

options
    :
    {
        $$ = make([]interface{}, 0)
    }
    | option options
    {
        opts := []interface{}{$1}
        $$ = append(opts, $2.([]interface{})...)
    }

option
    : '.' WHERE '(' IDENT ',' comparator ',' value ')'
    {
        $$ = WhereOption{Field: IdentExpr{Literal: $4.literal}, Comparator: $6.(Comparator), Value: $8}
    }
    | '.' ORDERBY '(' IDENT ',' direction ')'
    {
        $$ = OrderByOption{Field: IdentExpr{Literal: $4.literal}, DirectionDesc: $6.(bool)}
    }
    | '.' LIMIT '(' INT ')'
    {
        $$ = LimitOption{Limit: IntegerExpr{Literal: $4.literal}}
    }

comparator
    : EQ
    {
        $$ = ComparatorEq
    }

direction
    : ASC
    {
        $$ = false
    }
    | DESC
    {
        $$ = true
    }

value
    : STRING
    {
        $$ = StringExpr{Literal: $1.literal}
    }

%%

type lexer struct {
    scanner.Scanner
    result Query
}

func (l *lexer) Lex(lval *yySymType) int {
    token := int(l.Scan())
    switch token {
    case scanner.String:
        token = STRING
        lval.token = lexToken{token: token, literal: l.TokenText()}
    case scanner.Int:
        token = INT
        lval.token = lexToken{token: token, literal: l.TokenText()}
    case scanner.Ident:
        switch l.TokenText() {
        case "where":
            token = WHERE
        case "orderby":
            token = ORDERBY
        case "limit":
            token = LIMIT
        case "asc":
            token = ASC
        case "desc":
            token = DESC
        default:
            token = IDENT
        }
        lval.token = lexToken{token: token, literal: l.TokenText()}
    case '=':
        var literal string
        if l.Peek() == '=' {
            token = EQ
            l.Next()
            literal = "=="
        } else {
            literal = l.TokenText()
        }
        lval.token = lexToken{token: token, literal: literal}
    default:
        lval.token = lexToken{token: token, literal: l.TokenText()}
    }
    
    return token
}

func (l *lexer) Error(e string) {
    panic(errors.New(e))
}

func Parse(src io.Reader) (query Query, err error) {
    defer func(){
        if e := recover(); e != nil {
            err = e.(error)
        }
    }()

    l := &lexer{}
    l.Init(src)
    yyParse(l)

    query = l.result

    return
}
