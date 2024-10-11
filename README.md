# ezc - Easy Conf, an simple Configuration language

Version 0.1

## Table of Contents

1. [Table of Contents](#table-of-contents)
2. [Grammar](#grammar)
   2. [EBNF](#ebnf)

## Grammar

### EBNF

```EBNF
Statement           ::= (VariableAssignStmt | CategoryStmt) ';'
ValueAssignStmt     ::= VariableName '=' Literal
CategoryStmt        ::= '-' VariableName '-'
VariableName        ::= [a-zA-Z_] [a-zA-Z0-9_]*                 /* ws: explicit */
Literal             ::= IntegerLiteral
                        | FloatLiteral
                        | StringLiteral
                        | Array
                        | 'true'
                        | 'false'
IntegerLiteral      ::= Digits | HexIntegerLiteral | OctalIntegerLiteral
HexIntegerLiteral   ::= '0x' Hexs                               /* ws: explicit */
Hexs                ::= Hex+                                    /* ws: explicit */
Hex                 ::= [0-9a-fA-F]                             /* ws: explicit */
Digits              ::= [0-9]+                                  /* ws: explicit */
OctalIntegerLiteral ::= '0o' Octals                             /* ws: explicit */
Octals              ::= [0-7]+                                  /* ws: explicit */
FloatLiteral        ::= (Digits '.' Digits)
                        | ('.' Digits)
                        | (Digits '.')                          /* ws: explicit */
StringLiteral       ::= '"' StringContent* '"'                  /* ws: explicit */
StringContent       ::= [^""] | Escape                          /* ws: explicit */
Escape              ::= '\' EscapeChars                         /* ws: explicit */
EscapeChars         ::= [tnr\""] | Unicode
Unicode             ::= 'u' hex hex hex hex                     /* ws: explicit */
Array               ::= '[' Value ArrayValue* ']'
ArrayValue          ::= ',' Value
```
