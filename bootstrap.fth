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
: ELSE   IMMEDIATE  BR, CS> PATCH >CS ;

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

: HEXDIGIT ( u -- ch )
  DUP 10 < IF
    48 + EXIT
  THEN
  55 + ;

: PWRITE-HEX ( n -- )
  DUP 28 RSHIFT 15 AND HEXDIGIT EMIT
  DUP 24 RSHIFT 15 AND HEXDIGIT EMIT
  DUP 20 RSHIFT 15 AND HEXDIGIT EMIT
  DUP 16 RSHIFT 15 AND HEXDIGIT EMIT
  DUP 12 RSHIFT 15 AND HEXDIGIT EMIT
  DUP 8  RSHIFT 15 AND HEXDIGIT EMIT
  DUP 4  RSHIFT 15 AND HEXDIGIT EMIT
      15 AND HEXDIGIT EMIT ;

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

: PNEXT ( -- addr len )
  BEGIN
    PARSE-NAME
    DUP 0=
  WHILE
    2DROP
    REFILL 0= ABORT" read: unexpected EOF"
  REPEAT ;

: PREAD-I32 ( -- n )
  PNEXT
  2DUP NUMBER? IF
    >R 2DROP R> EXIT
  THEN
  2DROP ABORT" read integer: invalid token" ;

: PREAD-BOOL ( -- b )
  PREAD-I32 PBOOL ;

: PREADLN ( -- )
  #TIB @ >IN ! ;

: PREAD-CHAR ( -- u32 )
  PNEXT
  2DUP NUMBER? IF
    >R 2DROP R> EXIT
  THEN
  DUP 1 = IF
    DROP C@ EXIT
  THEN
  2DROP ABORT" read char: use codepoint or single char" ;

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

( ----- float32-on-cell IEEE754 binary32 bits ----- )
( finite normal/zero + simplified NaN/Inf support; subnormal inputs unsupported )

: 0<>  ( x -- f )  0= 0= ;
: 0<=  ( n -- f )  0> 0= ;
: 2*   ( x -- y )  DUP + ;
: 2/   ( x -- y )  1 RSHIFT ;
: ABS  ( n -- u )  DUP 0< IF NEGATE THEN ;
: ROT  ( a b c -- b c a )  >R SWAP R> SWAP ;

: F.SIGNMASK ( -- u )  1 31 LSHIFT ;
: F.EXPMAX   ( -- u )  255 ;
: F.EXPBIAS  ( -- u )  127 ;
: F.HIDDEN   ( -- u )  8388608 ;
: F.FRACMASK ( -- u )  8388607 ;
: F.OVF-MANT ( -- u )  16777216 ;
: F.EXPMASK  ( -- u )  2139095040 ;

: FSIGN    ( f -- s )    31 RSHIFT 1 AND ;
: FEXPRAW  ( f -- e )    23 RSHIFT 255 AND ;
: FFRAC    ( f -- frac ) F.FRACMASK AND ;
: FPACK    ( s e frac -- f )  ROT 31 LSHIFT ROT 23 LSHIFT OR OR ;

: FNEGATE  ( f -- f' )  F.SIGNMASK XOR ;
: FABS     ( f -- f' )
  DUP 31 RSHIFT 31 LSHIFT XOR ;

: F+INF    ( -- f )  0 255 0 FPACK ;
: F-INF    ( -- f )  1 255 0 FPACK ;
: FNAN     ( -- f )  0 255 4194304 FPACK ;   ( canonical qNaN )
: FSIGNED-ZERO ( s -- f )  0 0 FPACK ;
: FSPECIAL? ( f -- flag )  FEXPRAW 255 = ;
: FINF?    ( f -- flag )   DUP FEXPRAW 255 = SWAP FFRAC 0= AND ;
: FNAN?    ( f -- flag )   DUP FEXPRAW 255 = SWAP FFRAC 0<> AND ;
: FFINITE? ( f -- flag )   FEXPRAW 255 <> ;

: FZERO?   ( f -- flag )  FABS 0= ;
: F0=      ( f -- flag )  FZERO? ;

: FASSERT-FINITE ( f -- f )
  DUP FEXPRAW DUP 255 = IF
    DROP ABORT" float special unsupported"
  THEN
  DUP 0= IF
    DROP
    DUP FFRAC 0<> IF ABORT" float subnormal unsupported" THEN
    EXIT
  THEN
  DROP ;

: ULOG2 ( u -- p )
  0 SWAP
  BEGIN
    DUP 1 >
  WHILE
    1 RSHIFT
    SWAP 1+ SWAP
  REPEAT
  DROP ;

VARIABLE F_A
VARIABLE F_B
VARIABLE F_SA
VARIABLE F_SB
VARIABLE F_EA
VARIABLE F_EB
VARIABLE F_MA
VARIABLE F_MB
VARIABLE F_M
VARIABLE F_E
VARIABLE F_S
VARIABLE F_T

VARIABLE MUL_A
VARIABLE MUL_B
VARIABLE MUL_HI
VARIABLE MUL_LO
VARIABLE MUL_A0
VARIABLE MUL_A1
VARIABLE MUL_A2
VARIABLE MUL_B0
VARIABLE MUL_B1
VARIABLE MUL_B2
VARIABLE MUL_C0
VARIABLE MUL_C1
VARIABLE MUL_C2
VARIABLE MUL_C3
VARIABLE MUL_C4
VARIABLE MUL_CARRY
VARIABLE MUL_P0
VARIABLE MUL_P1
VARIABLE MUL_P2
VARIABLE MUL_P3
VARIABLE MUL_P4
VARIABLE MUL_P5

VARIABLE DIV_NUM
VARIABLE DIV_DEN
VARIABLE DIV_K
VARIABLE DIV_Q
VARIABLE DIV_R
VARIABLE FDEC.N
CREATE FDEC.BUF 16 ALLOT
VARIABLE FP.A
VARIABLE FP.L
VARIABLE FP.NEG
VARIABLE FP.INT
VARIABLE FP.FRAC
VARIABLE FP.SCALE
VARIABLE FP.DOT
VARIABLE FP.SEEN
VARIABLE FP.FDIG
VARIABLE FP.OK
VARIABLE FP.EXP
VARIABLE FP.ENEG
VARIABLE FP.INEXP
VARIABLE FP.ESEEN
VARIABLE FP.ESIGNOK

: XSWAP ( a1 a2 -- )
  2DUP @ SWAP @ ROT ! SWAP ! ;

: S>F ( n -- f )
  DUP 0= IF EXIT THEN
  DUP F.SIGNMASK = IF ABORT" S>F int32 min unsupported" THEN
  DUP 0< IF 1 ELSE 0 THEN F_S !
  ABS DUP ULOG2 DUP F_E !
  DUP 23 >= IF
    23 - RSHIFT
  ELSE
    23 SWAP - LSHIFT
  THEN
  F_M !
  F_S @
  F_E @ F.EXPBIAS + 
  F_M @ F.FRACMASK AND
  FPACK ;

: F>S ( f -- n )
  DUP FZERO? IF DROP 0 EXIT THEN
  FASSERT-FINITE
  DUP FSIGN F_S !
  DUP FEXPRAW F.EXPBIAS - DUP 0< IF DROP DROP 0 EXIT THEN F_E !
  DUP FFRAC F.HIDDEN OR F_M !
  DROP
  F_E @ 30 > IF ABORT" F>S overflow" THEN
  F_E @ 23 >= IF
    F_M @ F_E @ 23 - LSHIFT
  ELSE
    F_M @ 23 F_E @ - RSHIFT
  THEN
  F_S @ IF NEGATE THEN ;

: FSCALE2 ( f k -- f' )
  F_B ! F_A !
  F_A @ FZERO? IF F_B @ DROP F_A @ EXIT THEN
  F_A @ FASSERT-FINITE DROP
  F_A @ FSIGN F_S !
  F_A @ FEXPRAW F_B @ + DUP 0<= IF DROP 0 EXIT THEN
  DUP 255 >= IF DROP ABORT" float exponent overflow" THEN
  F_E !
  F_A @ FFRAC
  F_S @ F_E @ ROT FPACK ;

: Q16.16>F ( q -- f )
  S>F -16 FSCALE2 ;

: F>Q16.16 ( f -- q )
  16 FSCALE2 F>S ;

: F= ( f1 f2 -- flag )
  2DUP FNAN? SWAP FNAN? OR IF
    2DROP FALSE EXIT
  THEN
  2DUP FZERO? SWAP FZERO? AND IF
    2DROP TRUE EXIT
  THEN
  = ;

: F< ( f1 f2 -- flag )
  F_B ! F_A !
  F_A @ FNAN? F_B @ FNAN? OR IF FALSE EXIT THEN
  F_A @ FZERO? F_B @ FZERO? AND IF FALSE EXIT THEN
  F_A @ FSIGN F_SA !
  F_B @ FSIGN F_SB !
  F_SA @ F_SB @ <> IF
    F_SA @ EXIT
  THEN
  F_SA @ 0= IF
    F_A @ F_B @ <
  ELSE
    F_B @ F_A @ <
  THEN ;

: F<= ( f1 f2 -- flag )
  2DUP F< >R
  F=
  R> OR ;

: FHEX. ( f -- )  PWRITE-HEX SPACE ;

: UDEC. ( u -- )
  DUP 0= IF DROP 48 EMIT EXIT THEN
  0 FDEC.N !
  BEGIN
    DUP 0<>
  WHILE
    10 /MOD
    SWAP
    48 + FDEC.BUF FDEC.N @ + !
    FDEC.N @ 1+ FDEC.N !
  REPEAT
  DROP
  FDEC.N @ 0 DO
    FDEC.BUF FDEC.N @ 1- I - + @ EMIT
  LOOP ;

: UDEC4. ( u -- )
  DUP 1000 < IF 48 EMIT THEN
  DUP 100  < IF 48 EMIT THEN
  DUP 10   < IF 48 EMIT THEN
  UDEC. ;

: PWRITE-I32 ( n -- )
  DUP 0< IF
    DUP -2147483648 = IF
      DROP S" -2147483648" TYPE EXIT
    THEN
    45 EMIT
    NEGATE
  THEN
  UDEC. ;

: DIGIT? ( ch -- u true | false )
  DUP 48 < IF DROP FALSE EXIT THEN
  DUP 57 > IF DROP FALSE EXIT THEN
  48 - TRUE ;

: CLOWER ( ch -- ch' )
  DUP 65 >= OVER 90 <= AND IF 32 + THEN ;

: FP.ADV ( -- )
  FP.A @ 1+ FP.A !
  FP.L @ 1- FP.L ! ;

: FP-INF-TOK? ( -- flag )
  FP.L @ 3 = IF
    FP.A @ C@     CLOWER 105 = 
    FP.A @ 1+ C@  CLOWER 110 = AND
    FP.A @ 2 + C@ CLOWER 102 = AND
  ELSE
    FALSE
  THEN ;

: FP-NAN-TOK? ( -- flag )
  FP.L @ 3 = IF
    FP.A @ C@     CLOWER 110 = 
    FP.A @ 1+ C@  CLOWER 97  = AND
    FP.A @ 2 + C@ CLOWER 110 = AND
  ELSE
    FALSE
  THEN ;

: F.NORM-MANT ( f -- m )
  FFRAC F.HIDDEN OR ;

: F-DECODE2 ( f1 f2 -- )
  F_B ! F_A !
  F_A @ FZERO? 0= IF F_A @ FASSERT-FINITE DROP THEN
  F_B @ FZERO? 0= IF F_B @ FASSERT-FINITE DROP THEN
  F_A @ FSIGN F_SA !
  F_B @ FSIGN F_SB !
  F_A @ FEXPRAW F_EA !
  F_B @ FEXPRAW F_EB !
  F_A @ F_EA @ 0= IF DROP 0 ELSE F.NORM-MANT THEN F_MA !
  F_B @ F_EB @ 0= IF DROP 0 ELSE F.NORM-MANT THEN F_MB ! ;

: F-PACK-NORMAL ( s e mant24 -- f )
  >R
  DUP 0<= IF DROP R> DROP 0 EXIT THEN
  DUP 255 >= IF DROP R> DROP ABORT" float overflow" THEN
  R> F.FRACMASK AND
  FPACK ;

: FADD ( f1 f2 -- f3 )
  F_B ! F_A !
  F_A @ FNAN? F_B @ FNAN? OR IF FNAN EXIT THEN
  F_A @ FINF? F_B @ FINF? AND IF
    F_A @ FSIGN F_B @ FSIGN <> IF FNAN ELSE F_A @ THEN EXIT
  THEN
  F_A @ FINF? IF F_A @ EXIT THEN
  F_B @ FINF? IF F_B @ EXIT THEN

  F_A @ F_B @ F-DECODE2
  F_MA @ 0= IF F_B @ EXIT THEN
  F_MB @ 0= IF F_A @ EXIT THEN

  F_EA @ F_EB @ < IF
    F_SA F_SB XSWAP
    F_EA F_EB XSWAP
    F_MA F_MB XSWAP
  THEN

  F_EA @ F_EB @ - DUP 31 >= IF
    DROP 0 F_MB !
  ELSE
    F_MB @ SWAP RSHIFT F_MB !
  THEN

  F_SA @ F_SB @ = IF
    F_MA @ F_MB @ + F_M !
    F_SA @ F_S !
    F_EA @ F_E !
    F_M @ F.OVF-MANT >= IF
      F_M @ 1 RSHIFT F_M !
      F_E @ 1+ F_E !
    THEN
    F_S @ F_E @ F_M @ F-PACK-NORMAL EXIT
  THEN

  F_MA @ F_MB @ = IF 0 EXIT THEN
  F_MA @ F_MB @ < IF
    F_MA F_MB XSWAP
    F_SA F_SB XSWAP
  THEN
  F_MA @ F_MB @ - F_M !
  F_SA @ F_S !
  F_EA @ F_E !
  BEGIN
    F_M @ F.HIDDEN < F_E @ 1 > AND
  WHILE
    F_M @ 1 LSHIFT F_M !
    F_E @ 1- F_E !
  REPEAT
  F_M @ F.HIDDEN < IF 0 EXIT THEN
  F_S @ F_E @ F_M @ F-PACK-NORMAL ;

: FSUB ( f1 f2 -- f3 )
  FNEGATE FADD ;

: M24X24>48 ( a b -- hi lo )
  MUL_B ! MUL_A !
  MUL_A @       255 AND MUL_A0 !
  MUL_A @ 8  RSHIFT 255 AND MUL_A1 !
  MUL_A @ 16 RSHIFT 255 AND MUL_A2 !
  MUL_B @       255 AND MUL_B0 !
  MUL_B @ 8  RSHIFT 255 AND MUL_B1 !
  MUL_B @ 16 RSHIFT 255 AND MUL_B2 !

  MUL_A0 @ MUL_B0 @ * MUL_C0 !

  MUL_A0 @ MUL_B1 @ *   MUL_A1 @ MUL_B0 @ * + MUL_C1 !

  MUL_A0 @ MUL_B2 @ *   MUL_A1 @ MUL_B1 @ * +   MUL_A2 @ MUL_B0 @ * + MUL_C2 !

  MUL_A1 @ MUL_B2 @ *   MUL_A2 @ MUL_B1 @ * + MUL_C3 !
  MUL_A2 @ MUL_B2 @ * MUL_C4 !

  MUL_C0 @ 255 AND MUL_P0 !
  MUL_C0 @ 8 RSHIFT MUL_CARRY !

  MUL_C1 @ MUL_CARRY @ + DUP 255 AND MUL_P1 ! 8 RSHIFT MUL_CARRY !
  MUL_C2 @ MUL_CARRY @ + DUP 255 AND MUL_P2 ! 8 RSHIFT MUL_CARRY !
  MUL_C3 @ MUL_CARRY @ + DUP 255 AND MUL_P3 ! 8 RSHIFT MUL_CARRY !
  MUL_C4 @ MUL_CARRY @ + DUP 255 AND MUL_P4 ! 8 RSHIFT MUL_P5 !

  MUL_P0 @
  MUL_P1 @ 8 LSHIFT OR
  MUL_P2 @ 16 LSHIFT OR
  MUL_P3 @ 24 LSHIFT OR
  MUL_LO !

  MUL_P4 @
  MUL_P5 @ 8 LSHIFT OR
  MUL_HI !

  MUL_HI @ MUL_LO @ ;

: FMUL ( f1 f2 -- f3 )
  F_B ! F_A !
  F_A @ FNAN? F_B @ FNAN? OR IF FNAN EXIT THEN
  F_A @ FINF? F_B @ FZERO? AND IF FNAN EXIT THEN
  F_B @ FINF? F_A @ FZERO? AND IF FNAN EXIT THEN
  F_A @ FINF? F_B @ FINF? OR IF
    F_A @ FSIGN F_B @ FSIGN XOR 255 0 FPACK EXIT
  THEN

  F_A @ F_B @ F-DECODE2
  F_MA @ 0= IF F_SA @ F_SB @ XOR 0 0 FPACK EXIT THEN
  F_MB @ 0= IF F_SA @ F_SB @ XOR 0 0 FPACK EXIT THEN

  F_SA @ F_SB @ XOR F_S !
  F_EA @ F_EB @ + F.EXPBIAS - F_E !
  F_MA @ F_MB @ M24X24>48
  MUL_LO ! MUL_HI !

  MUL_HI @ 32768 AND IF
    F_E @ 1+ F_E !
    MUL_HI @ 8 LSHIFT
    MUL_LO @ 24 RSHIFT OR
    F_M !
  ELSE
    MUL_HI @ 9 LSHIFT
    MUL_LO @ 23 RSHIFT OR
    F_M !
  THEN
  F_S @ F_E @ F_M @ F-PACK-NORMAL ;

: UDIVSCALE ( num den k -- q )
  DIV_K ! DIV_DEN ! DIV_NUM !
  DIV_NUM @ DIV_DEN @ /MOD
  DIV_Q ! DIV_R !
  DIV_K @ 0 DO
    DIV_Q @ 1 LSHIFT DIV_Q !
    DIV_R @ 1 LSHIFT DIV_R !
    DIV_R @ DIV_DEN @ >= IF
      DIV_R @ DIV_DEN @ - DIV_R !
      DIV_Q @ 1+ DIV_Q !
    THEN
  LOOP
  DIV_Q @ ;

: FDIV ( f1 f2 -- f3 )
  F_B ! F_A !
  F_A @ FNAN? F_B @ FNAN? OR IF FNAN EXIT THEN
  F_A @ FINF? F_B @ FINF? AND IF FNAN EXIT THEN
  F_A @ FZERO? F_B @ FZERO? AND IF FNAN EXIT THEN
  F_B @ FZERO? IF
    F_A @ FSIGN F_B @ FSIGN XOR 255 0 FPACK EXIT
  THEN
  F_A @ FINF? IF
    F_A @ FSIGN F_B @ FSIGN XOR 255 0 FPACK EXIT
  THEN
  F_B @ FINF? IF
    F_A @ FSIGN F_B @ FSIGN XOR FSIGNED-ZERO EXIT
  THEN
  F_A @ FZERO? IF
    F_A @ FSIGN F_B @ FSIGN XOR FSIGNED-ZERO EXIT
  THEN

  F_A @ F_B @ F-DECODE2

  F_SA @ F_SB @ XOR F_S !
  F_EA @ F_EB @ - F.EXPBIAS + F_E !

  F_MA @ F_MB @ < IF
    F_E @ 1- F_E !
    F_MA @ F_MB @ 24 UDIVSCALE
  ELSE
    F_MA @ F_MB @ 23 UDIVSCALE
  THEN
  F_M !

  F_M @ F.HIDDEN < IF 0 EXIT THEN
  F_S @ F_E @ F_M @ F-PACK-NORMAL ;

: FNUMBER? ( addr len -- f true | false )
  FP.L ! FP.A !
  0 FP.NEG !
  0 FP.INT !
  0 FP.FRAC !
  1 FP.SCALE !
  0 FP.DOT !
  0 FP.SEEN !
  0 FP.FDIG !
  0 FP.EXP !
  0 FP.ENEG !
  0 FP.INEXP !
  0 FP.ESEEN !
  0 FP.ESIGNOK !
  TRUE FP.OK !

  FP.L @ 0= IF FALSE EXIT THEN

  FP.A @ C@ DUP 45 = IF
    DROP TRUE FP.NEG ! FP.ADV
  ELSE
    43 = IF FP.ADV THEN
  THEN

  FP-INF-TOK? IF
    FP.NEG @ IF F-INF ELSE F+INF THEN
    TRUE EXIT
  THEN
  FP-NAN-TOK? IF
    FNAN TRUE EXIT
  THEN

  BEGIN
    FP.L @ 0> FP.OK @ AND
  WHILE
    FP.A @ C@
    FP.INEXP @ IF
      DUP 101 = OVER 69 = OR IF
        DROP FALSE FP.OK !
      ELSE
        DUP 43 = OVER 45 = OR IF
          FP.ESIGNOK @ 0= IF
            DROP FALSE FP.OK !
          ELSE
            DUP 45 = IF TRUE FP.ENEG ! THEN
            DROP
            FALSE FP.ESIGNOK !
            FP.ADV
          THEN
        ELSE
          DIGIT? IF
            FP.EXP @ 10 * + FP.EXP !
            TRUE FP.ESEEN !
            FALSE FP.ESIGNOK !
            FP.ADV
          ELSE
            FALSE FP.OK !
          THEN
        THEN
      THEN
    ELSE
    DUP 46 = IF
      DROP
      FP.DOT @ IF FALSE FP.OK ! ELSE TRUE FP.DOT ! THEN
      FP.ADV
    ELSE
      DUP 101 = OVER 69 = OR IF
        DROP
        FP.SEEN @ 0= IF
          FALSE FP.OK !
        ELSE
          TRUE FP.INEXP !
          TRUE FP.ESIGNOK !
          0 FP.ESEEN !
          FP.ADV
        THEN
      ELSE
      DIGIT? IF
        TRUE FP.SEEN !
        FP.DOT @ IF
          FP.FDIG @ 9 >= IF
            DROP FALSE FP.OK !
          ELSE
            FP.FRAC @ 10 * + FP.FRAC !
            FP.SCALE @ 10 * FP.SCALE !
            FP.FDIG @ 1+ FP.FDIG !
          THEN
        ELSE
          FP.INT @ 10 * + FP.INT !
        THEN
        FP.ADV
      ELSE
        FALSE FP.OK !
      THEN
      THEN
    THEN
    THEN
  REPEAT

  FP.OK @ 0= IF FALSE EXIT THEN
  FP.SEEN @ 0= IF FALSE EXIT THEN
  FP.INEXP @ IF FP.ESEEN @ 0= IF FALSE EXIT THEN THEN

  FP.INT @ S>F
  FP.FDIG @ 0> IF
    FP.FRAC @ S>F
    FP.SCALE @ S>F
    FDIV
    FADD
  THEN
  BEGIN
    FP.EXP @ 0>
  WHILE
    FP.ENEG @ IF
      10 S>F FDIV
    ELSE
      10 S>F FMUL
    THEN
    FP.EXP @ 1- FP.EXP !
  REPEAT
  FP.NEG @ IF FNEGATE THEN
  TRUE ;

: READ-F32 ( c-addr u -- f flag )
  FNUMBER? ;

: PREAD-F32 ( -- f )
  PNEXT
  2DUP READ-F32 IF
    >R 2DROP R> EXIT
  THEN
  2DROP ABORT" read float: invalid token" ;

: F. ( f -- )
  DUP FNAN? IF DROP S" nan" TYPE EXIT THEN
  DUP FINF? IF
    DUP FSIGN IF
      DROP S" -inf" TYPE
    ELSE
      DROP S" inf" TYPE
    THEN
    EXIT
  THEN
  F>Q16.16
  DUP F.SIGNMASK = IF
    DROP S" -32768.0000" TYPE EXIT
  THEN
  DUP 0< IF
    45 EMIT
    NEGATE
  THEN
  DUP 65536 / UDEC.
  46 EMIT
  65536 MOD
  10000 * 65536 / UDEC4. ;

: WRITE-F32 ( f -- )
  F. ;

: PWRITE-F32 ( f -- )
  WRITE-F32 ;

: FROUND-I32 ( f -- n )
  DUP 0 S>F F< IF
    32768 Q16.16>F FSUB
  ELSE
    32768 Q16.16>F FADD
  THEN
  F>S ;

VARIABLE FTEST.FAIL
: FTEST-RESET ( -- )  0 FTEST.FAIL ! ;
: FTEST-FAIL  ( -- )  1 FTEST.FAIL ! ;
: FASSERT= ( got exp -- )
  = 0= IF FTEST-FAIL ABORT" FTEST assert" THEN ;

: FTEST-RUN ( -- )
  FTEST-RESET
  1 S>F 1065353216 FASSERT=
  -2 S>F -1073741824 FASSERT=
  3 S>F F>S 3 FASSERT=
  98304 Q16.16>F F>Q16.16 98304 FASSERT=
  1 S>F 2 S>F FADD F>S 3 FASSERT=
  5 S>F 2 S>F FSUB F>S 3 FASSERT=
  3 65536 * Q16.16>F 2 65536 * Q16.16>F FMUL F>Q16.16 393216 FASSERT=
  3 65536 * Q16.16>F 2 65536 * Q16.16>F FDIV F>Q16.16 98304 FASSERT=
  -1 S>F FNEGATE F>S 1 FASSERT=
  -1 S>F FABS F>S 1 FASSERT=
  0 S>F F0= TRUE FASSERT=
  1 S>F 2 S>F F< TRUE FASSERT=
  2 S>F 2 S>F F<= TRUE FASSERT=
  2 S>F 2 S>F F= TRUE FASSERT=
  F+INF FINF? TRUE FASSERT=
  F-INF FINF? TRUE FASSERT=
  FNAN FNAN? TRUE FASSERT=
  FNAN FNAN F= FALSE FASSERT=
  FNAN 1 S>F F< FALSE FASSERT=
  1 S>F 0 S>F FDIV FINF? TRUE FASSERT=
  0 S>F 0 S>F FDIV FNAN? TRUE FASSERT=
  F+INF F-INF FADD FNAN? TRUE FASSERT=
  F+INF 0 S>F FMUL FNAN? TRUE FASSERT=
  S" 1.5" FNUMBER? 0= IF ABORT" FNUMBER? fail" THEN F>Q16.16 98304 FASSERT=
  S" -.25" FNUMBER? 0= IF ABORT" FNUMBER? fail" THEN F>Q16.16 -16384 FASSERT=
  S" inf" FNUMBER? 0= IF ABORT" FNUMBER? fail" THEN FINF? TRUE FASSERT=
  S" -inf" FNUMBER? 0= IF ABORT" FNUMBER? fail" THEN FINF? TRUE FASSERT=
  S" nan" FNUMBER? 0= IF ABORT" FNUMBER? fail" THEN FNAN? TRUE FASSERT=
  S" 1e3" FNUMBER? 0= IF ABORT" FNUMBER? fail" THEN F>S 1000 FASSERT=
  S" 1.25e-1" FNUMBER? 0= IF ABORT" FNUMBER? fail" THEN F>Q16.16 8192 FASSERT=
  S" FTEST PASS" TYPE CR ;
PROMPT-ON
