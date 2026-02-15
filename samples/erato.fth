100 CONSTANT N
CREATE FLAG N 1+ ALLOT

: INIT
  N 1+ 0 DO  1 FLAG I + C!  LOOP ;

: MARK ( p -- )
  DUP DUP *      ( p p^2 )
  BEGIN
    DUP N <=
  WHILE
    0 OVER FLAG + C!
    OVER +
  REPEAT
  2DROP ;

: PRIMES
  INIT
  2
  BEGIN
    DUP N <=
  WHILE
    DUP FLAG + C@ IF
      DUP .
      DUP MARK
    THEN
    1+
  REPEAT
  DROP ;
