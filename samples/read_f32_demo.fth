( READ-F32 demo: parse float from string )
( Run with bootstrap loaded )
( cat bootstrap.fth; cat samples/read_f32_demo.fth; ... )

: SHOW-PARSE ( c-addr u -- )
  2DUP TYPE S"  -> " TYPE
  READ-F32 IF
    F. CR
  ELSE
    S" invalid" TYPE CR
  THEN ;

S" 3.1415" SHOW-PARSE
S" -2.5e1" SHOW-PARSE
S" nan" SHOW-PARSE
S" xyz" SHOW-PARSE

( WRITE-F32 / PWRITE-F32 aliases )
: SHOW-WRITE-DEMO
  S" 2.75" READ-F32 IF WRITE-F32 CR THEN
  S" -1.25" READ-F32 IF PWRITE-F32 CR THEN
;
SHOW-WRITE-DEMO
BYE
