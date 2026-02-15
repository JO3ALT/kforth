( ============================================================ )
( bootstrap.fth : self-extending REPL QUIT + minimal vocabulary )
( stdinから流し込み、最後にQUITを起動して以後もstdinで対話継続 )
( ============================================================ )

: BL 32 ;

: CONSTANT ( x "name" -- )  CREATE , DOES> @ ;
: VARIABLE ( "name" -- )    CREATE 0 , ;

: 1+   1 + ;
: 1-   1 - ;
: =    - 0= ;
: <>   = 0= ;
: NIP   SWAP DROP ;
: TUCK  SWAP OVER ;
: 2DUP  OVER OVER ;
: -ROT  SWAP >R SWAP R> ;
: TRUE  -1 ;
: FALSE 0 ;
: NEGATE  0 SWAP - ;

: CR     10 EMIT ;
: SPACE  32 EMIT ;

: <   ( a b -- f )  - 0< ;
: >   ( a b -- f )  SWAP < ;
: <=  ( a b -- f )  > 0= ;
: >=  ( a b -- f )  < 0= ;
: 0>  ( n -- f )    0 SWAP < ;

: WITHIN ( x lo hi -- f )  >R OVER < SWAP R> < AND ;

: /STRING ( addr len u -- addr' len' )
  TUCK - >R + R> ;

: TYPE ( addr len -- )
  0 DO
    DUP I + C@ EMIT
  LOOP
  DROP ;

: 2DROP DROP DROP ;

( ----- additions 1,2: comparisons/div/shifts wrappers ----- )
: /   ( a b -- q )  /MOD SWAP DROP ;
: MOD ( a b -- r )  /MOD DROP ;

( ----- compile-time control stack for IF/BEGIN... ----- )
CREATE CSP 0 ,
CREATE CSTACK  32 ALLOT

: >CS  ( x -- )
  CSP @ CSTACK + !
  CSP @ 1+ CSP ! ;

: CS>  ( -- x )
  CSP @ 1- DUP CSP !
  CSTACK + @ ;

: PATCH ( a -- )
  DUP HEREC SWAP - 1-   SWAP CODE! ;

: 0BR,  ( -- a )
  POSTPONE 0BRANCH
  HEREC 0 ,C ;

: BR,   ( -- a )
  POSTPONE BRANCH
  HEREC 0 ,C ;

: IF     IMMEDIATE  0BR, >CS ;
: THEN   IMMEDIATE  CS> PATCH ;
: ELSE   IMMEDIATE  BR, >CS  CS> PATCH ;

: BEGIN  IMMEDIATE  HEREC >CS ;
: AGAIN  IMMEDIATE  POSTPONE BRANCH  CS> HEREC 1+ - ,C ;
: UNTIL  IMMEDIATE  POSTPONE 0BRANCH CS> HEREC 1+ - ,C ;

: WHILE  IMMEDIATE  POSTPONE IF ;
: REPEAT IMMEDIATE  CS> >R POSTPONE BRANCH CS> HEREC 1+ - ,C R> PATCH ;

( ----- literals for compiler ----- )
: LITERAL  IMMEDIATE  POSTPONE LIT ,C ;

( ----- Pascal-style helper words ----- )
: PWRITE-I32  ( n -- )  . ;
: PWRITELN    ( -- )    CR ;
: PWRITE-STR  ( c-addr u -- ) TYPE ;

: PVAR@   ( addr -- x ) @ ;
: PVAR!   ( x addr -- ) ! ;
: PFIELD@ ( base ofs -- x ) + @ ;
: PFIELD! ( x base ofs -- ) + ! ;

: PBOOL ( x -- b )
  0= 1 AND 1 XOR ;

: PWRITE-BOOL ( b -- )
  PBOOL IF
    S" TRUE" TYPE
    EXIT
  THEN
  S" FALSE" TYPE ;

: PWRITE-CHAR ( u32 -- )
  DUP 128 < IF
    EMIT EXIT
  THEN
  DUP 2048 < IF
    DUP 6 RSHIFT 192 OR EMIT
    63 AND 128 OR EMIT
    EXIT
  THEN
  DUP 65536 < IF
    DUP 12 RSHIFT 224 OR EMIT
    DUP 6 RSHIFT 63 AND 128 OR EMIT
    63 AND 128 OR EMIT
    EXIT
  THEN
  DUP 1114112 < IF
    DUP 18 RSHIFT 240 OR EMIT
    DUP 12 RSHIFT 63 AND 128 OR EMIT
    DUP 6 RSHIFT 63 AND 128 OR EMIT
    63 AND 128 OR EMIT
    EXIT
  THEN
  DROP 63 EMIT ;

( ----- parsing ----- )
: PARSE-NAME  ( -- addr len )  BL PARSE ;

( ----- number conversion signed using >NUMBER and BASE ----- )
: (UNSIGNED) ( addr len -- u ok )
  0 -ROT              ( acc addr len )
  >NUMBER             ( acc addr' len' )
  NIP                 ( acc len' )
  0= ;                ( acc ok )

( ----- interpreter core ----- )
: INTERPRET
  BEGIN
    PARSE-NAME
    DUP 0= IF 2DROP EXIT THEN

    2DUP FIND
    DUP 0= IF
      DROP
      2DUP NUMBER? IF
        >R 2DROP R>          ( n )
        STATE @ IF
          POSTPONE LIT ,C
        THEN
      ELSE
        CR 63 EMIT SPACE
        2DUP TYPE
        2DROP
        EXIT
      THEN
    ELSE
      ( found: addr len xt flag )
      >R
      NIP NIP              ( xt )
      R>                   ( flag )
      STATE @ 0= IF
        DROP EXECUTE
      ELSE
        DUP -1 = IF
          DROP EXECUTE
        ELSE
          DROP ,C
        THEN
      THEN
    THEN
  AGAIN ;

: .OK  CR  111 EMIT 107 EMIT  SPACE ;  ( "ok " )

: QUIT
  BEGIN
    .OK
    REFILL 0= IF EXIT THEN
    INTERPRET
  AGAIN ;
PROMPT-ON
