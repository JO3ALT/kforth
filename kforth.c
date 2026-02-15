/*
  kFORTH-xt (32-bit) : stdin-only outer interpreter + VM

  Build:
    cc -O2 -Wall -Wextra -std=c11 kforth.c mf_io.c -o kforth

  Run (bootstrap + then REPL continues on stdin):
    cat bootstrap.fth - | ./kforth
*/

#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <setjmp.h>

#include "kf_io.h"
#include "kf_dev.h"
#include "kforth_api.h"

typedef int32_t  cell;
typedef uint32_t ucell;

#ifndef KFORTH_MEM_CODE_CELLS
#define KFORTH_MEM_CODE_CELLS 32768
#endif
#ifndef KFORTH_MEM_DATA_CELLS
#define KFORTH_MEM_DATA_CELLS 32768
#endif
#ifndef KFORTH_DS_DEPTH
#define KFORTH_DS_DEPTH 256
#endif
#ifndef KFORTH_RS_DEPTH
#define KFORTH_RS_DEPTH 256
#endif
#ifndef KFORTH_DICT_MAX
#define KFORTH_DICT_MAX 2048
#endif

enum { MEM_CODE_CELLS = KFORTH_MEM_CODE_CELLS, MEM_DATA_CELLS = KFORTH_MEM_DATA_CELLS };
enum { DS_DEPTH = KFORTH_DS_DEPTH, RS_DEPTH = KFORTH_RS_DEPTH };
enum { NAME_MAX = 15 };
enum { DICT_MAX = KFORTH_DICT_MAX };
enum { PRIM_MAX = 256 };
enum { CELL_BITS = (int)(sizeof(cell) * 8), CELL_BYTES = (int)sizeof(cell) };

#define WORD_TAG      0x80000000u
#define IS_WORDTOK(x) (((ucell)(x) & WORD_TAG) != 0)
#define WORD_ID(x)    ((int)((ucell)(x) & 0x7FFFFFFFu))
#define MK_WORDTOK(i) ((cell)(WORD_TAG | (ucell)(i)))

/* ===== VM state ===== */
static cell  code_mem[MEM_CODE_CELLS];
static cell  data_mem[MEM_DATA_CELLS];
static ucell here_code = 0;
static ucell here_data = 0;

static cell DS[DS_DEPTH];
static int  dsp = 0;
static cell RS[RS_DEPTH];
static int  rsp = 0;

static ucell ip = 0;
static int   running = 0;

/* ===== dictionary ===== */
typedef struct Word {
  int     link;
  char    name[NAME_MAX+1];
  uint8_t immediate;

  ucell   cfa;       /* primitive xt */
  ucell   pfa;       /* DOCOL: code addr, DOVAR/DODOES: data cell addr */
  ucell   does_ip;   /* DODOES: code addr */
} Word;

static Word dict[DICT_MAX];
static int  dict_n = 0;
static int  latest = -1;

static int last_created = -1;
static int current_wi = -1;
static int compiling = 0;
static int current_def = -1;

/* ===== primitive table ===== */
typedef void (*prim_fn)(void);
static prim_fn prim_table[PRIM_MAX];
static int prim_n = 0;

static ucell XT_EXIT, XT_LIT, XT_BRANCH, XT_0BRANCH;
static ucell XT_DOCOL, XT_DOVAR, XT_DODOES;
static ucell XT_DO, XT_LOOP, XT_PLOOP;
static ucell XT_XPOSTPONE, XT_XDOES;
static int WI_LIT = -1, WI_TYPE = -1, WI_ABORTQ = -1;

static void p_ABORT(void);
static void compile_wordtok(int wi);
static void execute_wi(int wi);

static jmp_buf recover_env;
static int recover_active = 0;
static int recover_requested = 0;

static void out_ch(char c){ mf_emit((uint8_t)c); }
static void out_str(const char *s){ while(*s) out_ch(*s++); }
static void out_nl(void){ out_ch('\n'); }
static void out_uint(unsigned long v){
  char buf[32];
  int n = 0;
  do{
    buf[n++] = (char)('0' + (v % 10u));
    v /= 10u;
  }while(v != 0u);
  while(n--) out_ch(buf[n]);
}
static void out_int(int v){
  if(v < 0){
    out_ch('-');
    out_uint((unsigned long)(-(long)v));
  }else{
    out_uint((unsigned long)v);
  }
}
static void out_err(const char *msg){
  out_str("? ");
  out_str(msg);
  out_nl();
}
static void out_err_i(const char *prefix, int v){
  out_str("? ");
  out_str(prefix);
  out_int(v);
  out_nl();
}
static void out_err_u(const char *prefix, unsigned long v){
  out_str("? ");
  out_str(prefix);
  out_uint(v);
  out_nl();
}

static void runtime_recover(const char *msg){
  out_nl();
  out_err(msg);
  dsp = 0;
  rsp = 0;
  running = 0;
  compiling = 0;
  current_def = -1;
  data_mem[0] = 0;         /* A_STATE */
  data_mem[2] = data_mem[3]; /* A_IN = A_NTIB */
  if(recover_active){
    recover_requested = 1;
    longjmp(recover_env, 1);
  }
  exit(1);
}

/* ===== stacks ===== */
static void dpush(cell v){ if(dsp>=DS_DEPTH){ runtime_recover("data stack overflow"); } DS[dsp++]=v; }
static cell dpop(void){
  if(dsp<=0){ runtime_recover("data stack underflow"); }
  return DS[--dsp];
}
static cell dpeek(void){
  if(dsp<=0){ runtime_recover("data stack underflow"); }
  return DS[dsp-1];
}

static void rpush(cell v){ if(rsp>=RS_DEPTH){ runtime_recover("return stack overflow"); } RS[rsp++]=v; }
static cell rpop(void){ if(rsp<=0){ runtime_recover("return stack underflow"); } return RS[--rsp]; }

/* ===== code/data memory ===== */
static void ccomma(cell v){
  if(here_code >= MEM_CODE_CELLS){ out_err("code full"); exit(1); }
  code_mem[here_code++] = v;
}
static void dcomma(cell v){
  if(here_data >= MEM_DATA_CELLS){ out_err("data full"); exit(1); }
  data_mem[here_data++] = v;
}

/* byte mapping onto data_mem (byte-addressed for C@ C! TIB etc.) */
static uint8_t fetch_byte(ucell byte_addr){
  ucell celli = byte_addr / (ucell)CELL_BYTES;
  ucell bsel  = byte_addr % (ucell)CELL_BYTES;
  ucell w = (ucell)data_mem[celli];
  return (uint8_t)((w >> (8u * bsel)) & 0xFFu);
}
static void store_byte(ucell byte_addr, uint8_t v){
  ucell celli = byte_addr / (ucell)CELL_BYTES;
  ucell bsel  = byte_addr % (ucell)CELL_BYTES;
  ucell sh = 8u * bsel;
  ucell mask = (ucell)0xFFu << sh;
  ucell w = (ucell)data_mem[celli];
  w = (w & ~mask) | (((ucell)v) << sh);
  data_mem[celli] = (cell)w;
}

/* ===== dictionary ===== */
static int add_word(const char *name, ucell cfa_xt, uint8_t imm){
  if(dict_n >= DICT_MAX){ out_err("dict full"); exit(1); }
  Word *w = &dict[dict_n];
  w->link = latest;
  strncpy(w->name, name, NAME_MAX);
  w->name[NAME_MAX]=0;
  w->immediate = imm;
  w->cfa = cfa_xt;
  w->pfa = 0;
  w->does_ip = 0;
  latest = dict_n;
  return dict_n++;
}

static int find_word_cstr(const char *name){
  for(int i=latest; i!=-1; i=dict[i].link){
    if(strcmp(dict[i].name, name)==0) return i;
  }
  return -1;
}

static ucell def_prim(const char *name, prim_fn fn, uint8_t imm){
  if(prim_n >= PRIM_MAX){ out_err("prim full"); exit(1); }
  ucell xt = (ucell)prim_n;
  prim_table[prim_n++] = fn;
  (void)add_word(name, xt, imm);
  return xt;
}

/* ===== execution ===== */
static void exec_cell(cell instr);

static void exec_word(int wi){
  if(wi < 0 || wi >= dict_n){ out_err_i("bad wi ", wi); exit(1); }
  current_wi = wi;
  ucell xt = dict[wi].cfa;
  if(xt >= (ucell)prim_n){ out_err_u("bad xt ", (unsigned)xt); exit(1); }
  prim_table[xt]();
}

static void run_thread(void){
  running = 1;
  while(running){
    cell instr = code_mem[ip++];
    exec_cell(instr);
  }
}

static void exec_cell(cell instr){
  if(IS_WORDTOK(instr)){
    exec_word(WORD_ID(instr));
  }else{
    ucell xt = (ucell)instr;
    if(xt >= (ucell)prim_n){ out_err_u("bad xt ", (unsigned)xt); exit(1); }
    prim_table[xt]();
  }
}

/* ===== reserved data layout for self-host REPL ===== */
enum { TIB_BYTES = 256, TIB_CELLS = (TIB_BYTES / CELL_BYTES) };
static const ucell A_STATE = 0;   /* cell: 0 interpret, 1 compile */
static const ucell A_BASE  = 1;   /* cell: radix */
static const ucell A_IN    = 2;   /* cell: >IN (byte index into TIB) */
static const ucell A_NTIB  = 3;   /* cell: #TIB (byte length) */
static const ucell A_TIB   = 4;   /* cells: TIB */

static void init_data_layout(void){
  data_mem[A_STATE] = 0;
  data_mem[A_BASE]  = 10;
  data_mem[A_IN]    = 0;
  data_mem[A_NTIB]  = 0;
  for(ucell i=0;i<TIB_CELLS;i++) data_mem[A_TIB+i]=0;
  here_data = (ucell)(A_TIB + TIB_CELLS);
}

/* ===== stdin-only token reader for C outer interpreter ===== */
static int prompt_mode = 0;
static int token_end_delim = '\n';

static void discard_to_eol(void){
  int c;
  while((c = mf_key()) >= 0){
    if(c == '\n') break;
  }
}

static int in_getch(void){
  return mf_key();
}

static int read_quoted(char *buf, size_t bufsz, int *out_len){
  int c;
  int n = 0;
  while(1){
    c = in_getch();
    if(c < 0){
      out_err("unterminated string");
      p_ABORT();
      return 0;
    }
    if(c == '"') break;
    if((size_t)n + 1 >= bufsz){
      out_err("string too long");
      p_ABORT();
      return 0;
    }
    buf[n++] = (char)c;
  }
  *out_len = n;
  return 1;
}

static cell alloc_string_data(const char *buf, int len){
  if(len < 0){ out_err("bad string length"); exit(1); }
  ucell cells = (ucell)((len + CELL_BYTES - 1) / CELL_BYTES);
  if((uint64_t)len > ((uint64_t)MEM_DATA_CELLS * (uint64_t)CELL_BYTES)){ out_err("string too big"); exit(1); }
  if(here_data + cells > MEM_DATA_CELLS){ out_err("data full"); exit(1); }
  ucell addr = (ucell)(here_data * (ucell)CELL_BYTES);
  for(int i=0;i<len;i++){
    store_byte((ucell)(addr + (ucell)i), (uint8_t)buf[i]);
  }
  for(int i=len; (i % CELL_BYTES) != 0; i++){
    store_byte((ucell)(addr + (ucell)i), 0);
  }
  here_data = (ucell)(here_data + cells);
  return (cell)addr;
}

static void compile_lit_cell(cell v){
  if(WI_LIT < 0){ out_err("no LIT"); exit(1); }
  compile_wordtok(WI_LIT);
  ccomma(v);
}

/* reads next whitespace-delimited token from stdin; returns 1/0 */
static int next_token(char *out, size_t outsz){
  int c;
  do{
    c = in_getch();
    if(c < 0) return 0;
  }while(isspace((unsigned char)c));

  size_t n=0;
  while(c >= 0 && !isspace((unsigned char)c)){
    if(n+1 < outsz) out[n++] = (char)c;
    c = in_getch();
  }
  token_end_delim = c;
  out[n]=0;
  return 1;
}

/* ===== primitives ===== */

/* core */
static void p_EXIT(void){
  ip = (ucell)rpop();
  if(rsp == 0) running = 0;
}
static void p_LIT(void){ dpush(code_mem[ip++]); }
static void p_BRANCH(void){
  if(data_mem[A_STATE] != 0){
    ccomma((cell)XT_BRANCH);
    return;
  }
  cell off = code_mem[ip++];
  ip = (ucell)((cell)ip + off);
}
static void p_0BRANCH(void){
  if(data_mem[A_STATE] != 0){
    ccomma((cell)XT_0BRANCH);
    return;
  }
  cell off = code_mem[ip++];
  cell f = dpop();
  if(f == 0) ip = (ucell)((cell)ip + off);
}

static void p_DOCOL(void){
  Word *w = &dict[current_wi];
  rpush((cell)ip);
  ip = w->pfa;
}
static void p_DOVAR(void){
  Word *w = &dict[current_wi];
  dpush((cell)w->pfa);
}
static void p_DODOES(void){
  Word *w = &dict[current_wi];
  dpush((cell)w->pfa);
  rpush((cell)ip);
  ip = w->does_ip;
}

/* stack */
static void p_DROP(void){ (void)dpop(); }
static void p_DUP(void){ cell a=dpeek(); dpush(a); }
static void p_SWAP(void){ cell b=dpop(), a=dpop(); dpush(b); dpush(a); }
static void p_OVER(void){ if(dsp<2){ runtime_recover("data stack underflow"); } dpush(DS[dsp-2]); }

/* arithmetic/logic */
static void p_ADD(void){ cell b=dpop(), a=dpop(); dpush((cell)(a+b)); }
static void p_SUB(void){ cell b=dpop(), a=dpop(); dpush((cell)(a-b)); }
static void p_MUL(void){ cell b=dpop(), a=dpop(); dpush((cell)(a*b)); }
static void p_AND(void){ cell b=dpop(), a=dpop(); dpush((cell)(a & b)); }
static void p_OR (void){ cell b=dpop(), a=dpop(); dpush((cell)(a | b)); }
static void p_XOR(void){ cell b=dpop(), a=dpop(); dpush((cell)(a ^ b)); }

/* comparisons: TRUE=-1, FALSE=0 */
static void p_ZEQ(void){
  cell a=dpop();
  dpush((cell)(a==0 ? -1 : 0));
}
static void p_0LT(void){
  cell a=dpop();
  dpush((cell)(a<0 ? -1 : 0));
}

/* data fetch/store (cell-addressed) */
static void p_FETCH(void){
  cell a = dpop();
  if(a < 0 || (ucell)a >= (ucell)MEM_DATA_CELLS){ out_err_i("@ bad ", a); exit(1); }
  dpush(data_mem[(ucell)a]);
}
static void p_STORE(void){
  cell a = dpop();
  cell v = dpop();
  if(a < 0 || (ucell)a >= (ucell)MEM_DATA_CELLS){ out_err_i("! bad ", a); exit(1); }
  data_mem[(ucell)a] = v;
}

/* byte fetch/store (byte-addressed) */
static void p_CAT(void){
  cell a = dpop();
  if(a < 0 || (((ucell)a) / (ucell)CELL_BYTES) >= (ucell)MEM_DATA_CELLS){
    out_err_i("C@ bad ", a);
    exit(1);
  }
  dpush((cell)fetch_byte((ucell)a));
}
static void p_CSTORE(void){
  cell a = dpop();
  cell v = dpop();
  if(a < 0 || (((ucell)a) / (ucell)CELL_BYTES) >= (ucell)MEM_DATA_CELLS){
    out_err_i("C! bad ", a);
    exit(1);
  }
  store_byte((ucell)a, (uint8_t)(v & 0xFF));
}

/* loops */
static void p_DO(void){
  if(data_mem[A_STATE] != 0){
    ccomma((cell)XT_DO);
    dpush((cell)here_code); /* loop body start */
    return;
  }
  cell index = dpop();
  cell limit = dpop();
  rpush(limit);
  rpush(index);
}
static void p_LOOP(void){
  if(data_mem[A_STATE] != 0){
    cell target = dpop();
    ccomma((cell)XT_LOOP);
    ccomma((cell)(target - (cell)(here_code + 1)));
    return;
  }
  cell off = code_mem[ip++];
  cell index = rpop();
  cell limit = rpop();
  index = (cell)(index + 1);
  if(index != limit){
    rpush(limit);
    rpush(index);
    ip = (ucell)((cell)ip + off);
  }
}
static void p_PLOOP(void){
  if(data_mem[A_STATE] != 0){
    cell target = dpop();
    ccomma((cell)XT_PLOOP);
    ccomma((cell)(target - (cell)(here_code + 1)));
    return;
  }
  cell off  = code_mem[ip++];
  cell step = dpop();
  cell index = rpop();
  cell limit = rpop();
  cell newi  = (cell)(index + step);

  int cont = 0;
  if(step > 0) cont = (newi < limit);
  else if(step < 0) cont = (newi >= limit);
  else cont = (index != limit);

  if(cont){
    rpush(limit);
    rpush(newi);
    ip = (ucell)((cell)ip + off);
  }
}
static void p_I(void){
  if(rsp < 2){ out_err("I RS underflow"); exit(1); }
  dpush(RS[rsp-1]);
}
static void p_J(void){
  if(rsp < 4){ out_err("J needs nested DO"); exit(1); }
  dpush(RS[rsp-3]);
}
static void p_UNLOOP(void){
  if(rsp < 2){ out_err("UNLOOP RS underflow"); exit(1); }
  (void)rpop(); (void)rpop();
}

/* return stack ops */
static void p_TOR(void){ rpush(dpop()); }
static void p_RFROM(void){ dpush(rpop()); }
static void p_RAT(void){ if(rsp<=0){ out_err("R@ underflow"); exit(1);} dpush(RS[rsp-1]); }

/* data-space mgmt */
static void p_HERE(void){ dpush((cell)here_data); }
static void p_ALLOT(void){
  cell n = dpop();
  if(n < 0){ out_err("ALLOT neg"); exit(1); }
  if((ucell)n > (MEM_DATA_CELLS - here_data)){ out_err("data full"); exit(1); }
  here_data = (ucell)(here_data + (ucell)n);
}
static void p_COMMA(void){ cell v=dpop(); dcomma(v); }

/* code-space helpers */
static void p_HEREC(void){ dpush((cell)here_code); }
static void p_CODEAT(void){
  cell a=dpop();
  if(a < 0 || (ucell)a >= (ucell)MEM_CODE_CELLS){ out_err_i("CODE@ bad ", a); exit(1); }
  dpush(code_mem[(ucell)a]);
}
static void p_CODESTORE(void){
  cell a=dpop();
  cell v=dpop();
  if(a < 0 || (ucell)a >= (ucell)MEM_CODE_CELLS){ out_err_i("CODE! bad ", a); exit(1); }
  code_mem[(ucell)a] = v;
}
static void p_CCOMMA(void){ cell v=dpop(); ccomma(v); }

/* I/O */
static void p_EMIT(void){ cell v=dpop(); mf_emit((uint8_t)v); }
static void p_KEY(void){ int c=mf_key(); if(c<0) dpush(0); else dpush((cell)(c & 0xFF)); }
static void p_DOT(void){ cell v=dpop(); out_int((int)v); out_ch(' '); }
static void p_IOAT(void){
  cell h = dpop();
  int32_t b = 0;
  int ok = kf_io_at((int32_t)h, &b);
  dpush((cell)b);
  dpush(ok ? (cell)-1 : (cell)0);
}
static void p_IOPUT(void){
  cell h = dpop();
  cell b = dpop();
  int ok = kf_io_put((int32_t)h, (int32_t)b);
  dpush(ok ? (cell)-1 : (cell)0);
}
static void p_IOCTL(void){
  cell h = dpop();
  cell req = dpop();
  cell x = dpop();
  int32_t y = 0;
  int ok = kf_io_ctl((int32_t)h, (int32_t)req, (int32_t)x, &y);
  dpush((cell)y);
  dpush(ok ? (cell)-1 : (cell)0);
}
static void p_TYPEP(void){
  cell len = dpop();
  cell addr = dpop();
  if(len < 0){ out_err("TYPE bad len"); exit(1); }
  for(int i=0;i<len;i++) mf_emit(fetch_byte((ucell)((cell)addr + i)));
}
static void p_PROMPTON(void){
  /* Enter interactive mode with clean stacks/state. */
  dsp = 0;
  rsp = 0;
  compiling = 0;
  current_def = -1;
  data_mem[A_STATE] = 0;
  prompt_mode = 1;
}
static void p_PROMPTOFF(void){
  prompt_mode = 0;
}
static void p_BYE(void){ exit(0); }
static void p_ABORTQ(void){
  cell len = dpop();
  cell addr = dpop();
  cell flag = dpop();
  if(flag == 0) return;
  if(len < 0){ out_err("ABORT\" bad len"); exit(1); }
  mf_emit('\n');
  for(int i=0;i<len;i++) mf_emit(fetch_byte((ucell)((cell)addr + i)));
  p_ABORT();
}
static void p_SQUOTE(void){
  char buf[1024];
  int len = 0;
  if(!read_quoted(buf, sizeof(buf), &len)) return;
  cell addr = alloc_string_data(buf, len);
  if(data_mem[A_STATE] != 0){
    compile_lit_cell(addr);
    compile_lit_cell((cell)len);
  }else{
    dpush(addr);
    dpush((cell)len);
  }
}
static void p_DOTQUOTE(void){
  char buf[1024];
  int len = 0;
  if(!read_quoted(buf, sizeof(buf), &len)) return;
  cell addr = alloc_string_data(buf, len);
  if(data_mem[A_STATE] != 0){
    if(WI_TYPE < 0){ out_err("no TYPE"); exit(1); }
    compile_lit_cell(addr);
    compile_lit_cell((cell)len);
    compile_wordtok(WI_TYPE);
  }else{
    for(int i=0;i<len;i++) mf_emit((uint8_t)buf[i]);
  }
}
static void p_ABORTQUOTE(void){
  char buf[1024];
  int len = 0;
  if(!read_quoted(buf, sizeof(buf), &len)) return;
  cell addr = alloc_string_data(buf, len);
  if(data_mem[A_STATE] != 0){
    if(WI_ABORTQ < 0){ out_err("no (ABORT\")"); exit(1); }
    compile_lit_cell(addr);
    compile_lit_cell((cell)len);
    compile_wordtok(WI_ABORTQ);
  }else{
    cell flag = dpop();
    if(flag == 0) return;
    mf_emit('\n');
    for(int i=0;i<len;i++) mf_emit((uint8_t)buf[i]);
    p_ABORT();
  }
}

/* EXECUTE: word-token or primitive xt */
static void p_EXECUTE(void){
  cell x = dpop();
  if(IS_WORDTOK(x)){
    int wi = WORD_ID(x);
    Word *w = &dict[wi];
    if((w->cfa == XT_DOCOL || w->cfa == XT_DODOES) && !running){
      ucell saved_ip = ip;
      ip = 0;
      exec_word(wi);
      run_thread();
      ip = saved_ip;
    }else{
      exec_word(wi);
    }
  }else{
    ucell xt=(ucell)x;
    if(xt >= (ucell)prim_n){ out_err("EXECUTE bad xt"); exit(1); }
    prim_table[xt]();
  }
}

/* comment: ( ... ) reads from stdin via mf_key */
static void p_PAREN_COMMENT(void){
  int c;
  while((c = mf_key()) != -1){
    if(c == ')') break;
  }
}

/* REPL interface primitives */
static void p_STATE(void){ dpush((cell)A_STATE); }
static void p_BASE(void){ dpush((cell)A_BASE); }
static void p_IN(void){ dpush((cell)A_IN); }
static void p_NTIB(void){ dpush((cell)A_NTIB); }
static void p_TIB(void){ dpush((cell)(A_TIB * (ucell)CELL_BYTES)); } /* byte address */

/* [ ] */
static void p_LBRACK(void){ data_mem[A_STATE] = 0; }
static void p_RBRACK(void){
  if(current_def >= 0) data_mem[A_STATE] = 1;
}

/* REFILL: read a line into TIB; returns flag */
static void p_REFILL(void){
  ucell n=0;
  int c;
  while(1){
    c = mf_key();
    if(c < 0){
      if(n==0){ data_mem[A_NTIB]=0; dpush(0); return; }
      break;
    }
    if(c=='\r') continue;
    if(c=='\n') break;
    if(n < (TIB_BYTES-1)){
      store_byte((ucell)(A_TIB*(ucell)CELL_BYTES) + n, (uint8_t)(c & 0xFF));
      n++;
    }
  }
  store_byte((ucell)(A_TIB*(ucell)CELL_BYTES) + n, 0);
  data_mem[A_NTIB] = (cell)n;
  data_mem[A_IN]   = 0;
  dpush(1);
}

/* SOURCE: ( -- addr len ) */
static void p_SOURCE(void){
  dpush((cell)(A_TIB*(ucell)CELL_BYTES));
  dpush(data_mem[A_NTIB]);
}

/* PARSE: ( delim -- addr len ) using SOURCE and >IN */
static void p_PARSE(void){
  cell delim = dpop();
  ucell base = (ucell)(A_TIB*(ucell)CELL_BYTES);
  ucell ntib = (ucell)data_mem[A_NTIB];
  ucell in   = (ucell)data_mem[A_IN];

  if(in >= ntib){
    char buf[1024];
    int c;
    int n = 0;
    while(1){
      c = mf_key();
      if(c < 0 || c == '\n') break;
      if((uint8_t)c != (uint8_t)(delim & 0xFF)) break;
    }
    while(c >= 0 && c != '\n' && (uint8_t)c != (uint8_t)(delim & 0xFF)){
      if(n < (int)sizeof(buf)-1) buf[n++] = (char)c;
      c = mf_key();
    }
    cell addr = alloc_string_data(buf, n);
    dpush(addr);
    dpush((cell)n);
    return;
  }

  while(in < ntib && fetch_byte(base + in) == (uint8_t)(delim & 0xFF)) in++;
  ucell start=in;
  while(in < ntib && fetch_byte(base + in) != (uint8_t)(delim & 0xFF)) in++;
  ucell len = in - start;
  if(in < ntib && fetch_byte(base + in) == (uint8_t)(delim & 0xFF)) in++;
  data_mem[A_IN] = (cell)in;

  dpush((cell)(base + start));
  dpush((cell)len);
}

/* FIND: ( addr len -- xt 1 | xt -1 | 0 )  xt is word-token */
static void p_FIND(void){
  cell len=dpop();
  cell addr=dpop();
  if(len <= 0){ dpush(0); return; }

  char buf[NAME_MAX+1];
  int n = (len > NAME_MAX) ? NAME_MAX : (int)len;
  for(int i=0;i<n;i++) buf[i] = (char)fetch_byte((ucell)addr + (ucell)i);
  buf[n]=0;

  int wi = find_word_cstr(buf);
  if(wi < 0) dpush(0);
  else{
    dpush(MK_WORDTOK(wi));
    dpush(dict[wi].immediate ? (cell)-1 : (cell)1);
  }
}

/* ' : uses PARSE BL then FIND, leaves xt */
static void p_TICK(void){
  char tok[128];
  ucell ntib = (ucell)data_mem[A_NTIB];
  ucell in   = (ucell)data_mem[A_IN];

  if(in < ntib){
    dpush(32);
    p_PARSE();
    p_FIND();
    cell f = dpop();
    if(f!=0) return; /* xt is already on stack */
  }

  if(!next_token(tok, sizeof(tok))){ out_err("' ?"); exit(1); }
  int wi = find_word_cstr(tok);
  if(wi < 0){ out_err("' ?"); exit(1); }
  dpush(MK_WORDTOK(wi));
}

static void p_BRACKTICK(void){
  if(data_mem[A_STATE] == 0){
    out_err("['] outside compile");
    return;
  }
  p_TICK();
  compile_lit_cell(dpop());
}

/* POSTPONE: compile next xt regardless of immediate */
static void p_XPOSTPONE(void){
  cell xt = dpop();
  if(!IS_WORDTOK(xt)){ out_err("POSTPONE bad xt"); exit(1); }
  int wi = WORD_ID(xt);
  if(wi < 0 || wi >= dict_n){ out_err("POSTPONE bad wi"); exit(1); }
  if(data_mem[A_STATE] != 0){
    if(dict[wi].immediate) execute_wi(wi);
    else compile_wordtok(wi);
  }else{
    execute_wi(wi);
  }
}

static void p_POSTPONE(void){
  char tok[128];
  cell xt;
  ucell ntib = (ucell)data_mem[A_NTIB];
  ucell in   = (ucell)data_mem[A_IN];

  if(in < ntib){
    dpush(32);
    p_PARSE();
    p_FIND();
    cell f = dpop();
    if(f!=0){
      xt = dpop();
    }else{
      if(!next_token(tok, sizeof(tok))){ out_err("POSTPONE ?"); exit(1); }
      int wi = find_word_cstr(tok);
      if(wi < 0){ out_err("POSTPONE ?"); exit(1); }
      xt = MK_WORDTOK(wi);
    }
  }else{
    if(!next_token(tok, sizeof(tok))){ out_err("POSTPONE ?"); exit(1); }
    int wi = find_word_cstr(tok);
    if(wi < 0){ out_err("POSTPONE ?"); exit(1); }
    xt = MK_WORDTOK(wi);
  }
  if(data_mem[A_STATE] == 0){
    out_err("POSTPONE outside compile");
    return;
  }
  compile_lit_cell(xt);
  if(XT_XPOSTPONE >= (ucell)prim_n){ out_err("no (POSTPONE)"); exit(1); }
  ccomma((cell)XT_XPOSTPONE);
}

static void p_XDOES(void){
  if(last_created < 0){ out_err("(DOES>) no CREATE"); exit(1); }
  dict[last_created].cfa = XT_DODOES;
  dict[last_created].does_ip = ip;
  ip = (ucell)rpop();
  if(rsp == 0) running = 0;
}

/* >NUMBER: ( u addr len -- u' addr' len' ) in BASE, unsigned cell-width */
static int digit_val(int c){
  if(c>='0' && c<='9') return c-'0';
  if(c>='A' && c<='Z') return 10 + (c-'A');
  if(c>='a' && c<='z') return 10 + (c-'a');
  return -1;
}
static void p_TONUMBER(void){
  ucell len = (ucell)dpop();
  ucell addr = (ucell)dpop();
  ucell acc = (ucell)dpop();

  ucell base = (ucell)data_mem[A_BASE];
  if(base < 2 || base > 36) base = 10;

  ucell i=0;
  while(i < len){
    int dv = digit_val((int)fetch_byte(addr + i));
    if(dv < 0 || (ucell)dv >= base) break;
    acc = (ucell)(acc * base + (ucell)dv);
    i++;
  }

  dpush((cell)acc);
  dpush((cell)(addr + i));
  dpush((cell)(len - i));
}

/* NUMBER?: ( addr len -- n true | false ) */
static void p_NUMBERQ(void){
  cell len_in = dpop();
  cell addr_in = dpop();
  if(len_in <= 0){
    dpush(0);
    return;
  }

  ucell addr = (ucell)addr_in;
  ucell len = (ucell)len_in;
  int neg = 0;
  if(fetch_byte(addr) == (uint8_t)'-'){
    neg = 1;
    addr++;
    if(len == 0){
      dpush(0);
      return;
    }
    len--;
    if(len == 0){
      dpush(0);
      return;
    }
  }

  ucell base = (ucell)data_mem[A_BASE];
  if(base < 2 || base > 36) base = 10;

  ucell acc = 0;
  for(ucell i=0; i<len; i++){
    int dv = digit_val((int)fetch_byte(addr + i));
    if(dv < 0 || (ucell)dv >= base){
      dpush(0);
      return;
    }
    acc = (ucell)(acc * base + (ucell)dv);
  }

  if(neg){
    dpush((cell)(-((cell)acc)));
  }else{
    dpush((cell)acc);
  }
  dpush((cell)-1);
}

/* ABORT: reset stacks, keep VM running, discard rest of line */
static void p_ABORT(void){
  dsp = 0;
  rsp = 0;
  compiling = 0;
  current_def = -1;
  data_mem[A_STATE] = 0;
  data_mem[A_IN] = data_mem[A_NTIB];
  running = 0;
}

/* shifts (logical, cell-width) */
static void p_LSHIFT(void){
  cell u = dpop();
  cell x = dpop();
  ucell s = (ucell)u;
  ucell v = (ucell)x;
  if(s >= (ucell)CELL_BITS) v = 0;
  else v = (ucell)(v << s);
  dpush((cell)v);
}
static void p_RSHIFT(void){
  cell u = dpop();
  cell x = dpop();
  ucell s = (ucell)u;
  ucell v = (ucell)x;
  if(s >= (ucell)CELL_BITS) v = 0;
  else v = (ucell)(v >> s);
  dpush((cell)v);
}

/* signed /MOD ( a b -- rem quot ) */
static void p_DIVMOD(void){
  cell b = dpop();
  cell a = dpop();
  if(b == 0){
    out_err("/MOD divide by zero");
    p_ABORT();
    return;
  }
  if(a == INT32_MIN && b == (cell)-1){
    dpush((cell)0);
    dpush((cell)INT32_MIN);
    return;
  }
  cell q = (cell)(a / b);
  cell r = (cell)(a % b);
  dpush(r);
  dpush(q);
}

/* debug */
static void p_DEPTH(void){ dpush((cell)dsp); }

static void p_DOTS(void){ /* .S */
  out_ch('<');
  out_int(dsp);
  out_str("> ");
  for(int i=0;i<dsp;i++){
    out_int((int)DS[i]);
    out_ch(' ');
  }
}

static void p_WORDS(void){
  for(int i=latest; i!=-1; i=dict[i].link){
    out_str(dict[i].name);
    out_ch(' ');
  }
  out_nl();
}

/* ===== C-side defining words (needed to load bootstrap) ===== */

static void compile_wordtok(int wi){ ccomma(MK_WORDTOK(wi)); }

static int parse_number_c(const char *s, cell *out){
  char *end=NULL;
  long v = strtol(s, &end, 0);
  if(end==s || *end!=0) return 0;
  if(v < INT32_MIN || v > INT32_MAX) return 0;
  *out = (cell)v;
  return 1;
}

static void p_COLON(void){
  char name[128];
  if(!next_token(name, sizeof(name))){ out_err(": needs name"); return; }
  int wi = add_word(name, XT_DOCOL, 0);
  dict[wi].pfa = here_code;
  compiling = 1;
  current_def = wi;
  data_mem[A_STATE] = 1;
}
static void p_SEMI(void){
  if(!compiling){ out_err("; outside"); return; }
  ccomma((cell)XT_EXIT);
  compiling = 0;
  current_def = -1;
  data_mem[A_STATE] = 0;
}
static void p_IMMEDIATE(void){
  if(latest < 0){ out_err("IMMEDIATE no latest"); return; }
  dict[latest].immediate = 1;
}
static void p_CREATE(void){
  char name[128];
  if(!next_token(name, sizeof(name))){ out_err("CREATE needs name"); return; }
  int wi = add_word(name, XT_DOVAR, 0);
  dict[wi].pfa = here_data;
  last_created = wi;
}
static void p_DOES(void){
  if(!compiling){ out_err("DOES> only during compile"); return; }
  if(XT_XDOES >= (ucell)prim_n){ out_err("no (DOES>)"); exit(1); }
  ccomma((cell)XT_XDOES);
}

/* ===== init core ===== */
static void init_core(void){
  init_data_layout();

  XT_EXIT    = def_prim("EXIT",    p_EXIT,    0);
  XT_LIT     = def_prim("LIT",     p_LIT,     0);
  XT_BRANCH  = def_prim("BRANCH",  p_BRANCH,  0);
  XT_0BRANCH = def_prim("0BRANCH", p_0BRANCH, 0);

  XT_DOCOL   = def_prim("DOCOL",   p_DOCOL,   0);
  XT_DOVAR   = def_prim("DOVAR",   p_DOVAR,   0);
  XT_DODOES  = def_prim("DODOES",  p_DODOES,  0);

  def_prim("DROP", p_DROP, 0);
  def_prim("DUP",  p_DUP,  0);
  def_prim("SWAP", p_SWAP, 0);
  def_prim("OVER", p_OVER, 0);

  def_prim("+",   p_ADD, 0);
  def_prim("-",   p_SUB, 0);
  def_prim("*",   p_MUL, 0);
  def_prim("AND", p_AND, 0);
  def_prim("OR",  p_OR,  0);
  def_prim("XOR", p_XOR, 0);
  def_prim("0=",  p_ZEQ, 0);
  def_prim("0<",  p_0LT, 0);

  def_prim("@",  p_FETCH, 0);
  def_prim("!",  p_STORE, 0);
  def_prim("C@", p_CAT,   0);
  def_prim("C!", p_CSTORE,0);

  def_prim(">R", p_TOR,   0);
  def_prim("R>", p_RFROM, 0);
  def_prim("R@", p_RAT,   0);

  XT_DO    = def_prim("DO",    p_DO,    1);
  XT_LOOP  = def_prim("LOOP",  p_LOOP,  1);
  XT_PLOOP = def_prim("+LOOP", p_PLOOP, 1);
  def_prim("I",     p_I,     0);
  def_prim("J",     p_J,     0);
  def_prim("UNLOOP",p_UNLOOP,0);

  def_prim("HERE",  p_HERE,  0);
  def_prim("ALLOT", p_ALLOT, 0);
  def_prim(",",     p_COMMA, 0);

  def_prim("HEREC", p_HEREC,     0);
  def_prim("CODE@", p_CODEAT,    0);
  def_prim("CODE!", p_CODESTORE, 0);
  def_prim(",C",    p_CCOMMA,    0);

  def_prim("EMIT", p_EMIT, 0);
  def_prim("KEY",  p_KEY,  0);
  def_prim(".",    p_DOT,  0);
  def_prim("IO@",  p_IOAT, 0);
  def_prim("IO!",  p_IOPUT, 0);
  def_prim("IOCTL",p_IOCTL, 0);
  def_prim("TYPE", p_TYPEP, 0);
  def_prim("PROMPT-ON", p_PROMPTON, 0);
  def_prim("PROMPT-OFF", p_PROMPTOFF, 0);
  def_prim("BYE", p_BYE, 0);
  def_prim("(ABORT\")", p_ABORTQ, 0);

  def_prim("S\"", p_SQUOTE, 1);
  def_prim(".\"", p_DOTQUOTE, 1);
  def_prim("ABORT\"", p_ABORTQUOTE, 1);

  def_prim("EXECUTE", p_EXECUTE, 0);

  def_prim("(", p_PAREN_COMMENT, 1);

  /* self-host REPL primitives */
  def_prim("STATE",  p_STATE,  0);
  def_prim("BASE",   p_BASE,   0);
  def_prim(">IN",    p_IN,     0);
  def_prim("#TIB",   p_NTIB,   0);
  def_prim("TIB",    p_TIB,    0);
  def_prim("SOURCE", p_SOURCE, 0);
  def_prim("REFILL", p_REFILL, 0);
  def_prim("PARSE",  p_PARSE,  0);
  def_prim("FIND",   p_FIND,   0);
  def_prim("'",      p_TICK,   0);
  def_prim("[']",    p_BRACKTICK, 1);
  def_prim("POSTPONE", p_POSTPONE, 1);
  XT_XPOSTPONE = def_prim("(POSTPONE)", p_XPOSTPONE, 0);
  def_prim("[",      p_LBRACK, 1);
  def_prim("]",      p_RBRACK, 1);
  def_prim(">NUMBER",p_TONUMBER,0);
  def_prim("NUMBER?",p_NUMBERQ,0);
  def_prim("ABORT",  p_ABORT,  0);

  /* additions: division/shift/debug */
  def_prim("/MOD",   p_DIVMOD, 0);
  def_prim("LSHIFT", p_LSHIFT, 0);
  def_prim("RSHIFT", p_RSHIFT, 0);
  def_prim("DEPTH",  p_DEPTH,  0);
  def_prim(".S",     p_DOTS,   0);
  def_prim("WORDS",  p_WORDS,  0);

  /* definers for bootstrap-loading */
  def_prim(":",         p_COLON,     1);
  def_prim(";",         p_SEMI,      1);
  def_prim("IMMEDIATE", p_IMMEDIATE, 1);
  def_prim("CREATE",    p_CREATE,    0);
  def_prim("DOES>",     p_DOES,      1);
  XT_XDOES = def_prim("(DOES>)", p_XDOES, 0);

  WI_LIT = find_word_cstr("LIT");
  WI_TYPE = find_word_cstr("TYPE");
  WI_ABORTQ = find_word_cstr("(ABORT\")");
}

/* ===== C outer interpreter: stdin-only ===== */
static void execute_wi(int wi){
  Word *w = &dict[wi];
  if(w->cfa == XT_DOCOL || w->cfa == XT_DODOES){
    ucell saved_ip = ip;
    ip = 0;
    exec_word(wi);
    run_thread();
    ip = saved_ip;
  }else{
    exec_word(wi);
  }
}

static void interpret_token(const char *t){
  int wi = find_word_cstr(t);
  cell n;

  compiling = (data_mem[A_STATE] != 0);

  if(wi >= 0){
    Word *w = &dict[wi];
    if(compiling && !w->immediate){
      compile_wordtok(wi);
    }else{
      execute_wi(wi);
    }
    return;
  }

  if(parse_number_c(t, &n)){
    if(compiling){
      int w_lit = find_word_cstr("LIT");
      if(w_lit < 0){ out_err("no LIT"); exit(1); }
      compile_wordtok(w_lit);
      ccomma(n);
    }else{
      dpush(n);
    }
    return;
  }

  out_str("? ");
  out_str(t);
  out_nl();
  p_ABORT();
}

int kforth_run(void){
  init_core();

  char tok[128];
  while(next_token(tok, sizeof(tok))){
    if(setjmp(recover_env) == 0){
      recover_active = 1;
      recover_requested = 0;
      interpret_token(tok);
      recover_active = 0;
      if(prompt_mode && token_end_delim == '\n'){
        out_nl();
        out_str("ok ");
      }
    }else{
      recover_active = 0;
      if(recover_requested){
        if(token_end_delim != '\n' && token_end_delim != '\r' && token_end_delim >= 0){
          discard_to_eol();
        }
        if(prompt_mode){
          out_nl();
          out_str("ok ");
        }
        recover_requested = 0;
      }
    }
  }
  return 0;
}

#ifndef KFORTH_NO_MAIN
int main(void){
  return kforth_run();
}
#endif
