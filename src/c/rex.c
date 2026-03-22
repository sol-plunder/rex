// Copyright (c) 2026 xoCore Technologies
// SPDX-License-Identifier: MIT
// See LICENSE for full terms.

/*
    ### Testing and Cleanup:

    TODO: Do careful testing of the handling of heirs in layout mode.

    TODO: Write cleaner code for loading string literals.

--------------------------------------------------------------------------------

    TODO Just print everything in closed mode

    TODO Just print things wrapped in most error cases.

    TODO WASM demo.

--------------------------------------------------------------------------------

    S-expression style pretty-printing.

    (? f [x y] x)

    (f 3 4 5 6)

    (f 3 4 5 6
      (^ a b c d e f g)
      7 8 9 10
      (- a b c d e f g))

    (f 3 4 5 'slug
    )

    (f 3 4 5 '''
             ugly
             ''')

    (f 3 4 5 "trad
              string")

    (f 3 4 5 'quip(foo)bar)

    Decision criteria:

    -   Is the output of printing the rex thing normal and have small output?

    # TODO: Idea about adding another pass:

    Can we simplify this code by parsing in this tree shape:

        data Leaf = WORD Text -- More, but not relevant to parser complexity
        data Node = RUNE Text | LEAF Leaf | CHILD Tree
        data Tree = TREE Shape [Node] (Maybe Node)
        data Shape = PAREN | BRACE | CURLY | CLEAR | CLUMP | POEM | BLOCK | ITEM

    The idea is that this directly matches the "stack of contexts" state
    machine, and if this indeed includes enough information to be able
    to convert it to the correct Rex, then this moves A LOT of details
    out of the parser, which would make this a lot easier to work with.

*/

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>


// Utils ///////////////////////////////////////////////////////////////////////

#define DEBUG 0

#define debugf(...) if (DEBUG) fprintf(stderr, __VA_ARGS__);

void _Noreturn die (char *reason) {
    fprintf(stderr, "\n\nCRASH! <<<%s>>>\n\n", reason);
    exit(1);
}


// CLI Options /////////////////////////////////////////////////////////////////

typedef enum {
    CMD_LEX, CMD_NEST, CMD_SPLIT, CMD_QUIP, CMD_PARSE, CMD_CMP
} Cmd;

typedef struct { Cmd cmd; bool color, wrap; char *r1, *r2; } Config;

Config conf;

static inline _Noreturn void usage (void) {
    printf("rex [--no-color]\n");
    printf("rex (lex | nest | slug | split | quip | parse) [--no-color | --wrap]\n");
    printf("rex cmd rune rune\n");
    exit(2);
}

static inline Config argparse (int argc, char **argv) {
    if (argc==1) return (Config){CMD_PARSE, true, 0, 0};

    if (!strcmp(argv[1], "--no-color")) {
        if (argc != 2) usage();
        return (Config){CMD_PARSE, false, false, 0, 0};
    }

    // TODO: support --wrap --no-color at the same time
    if (!strcmp(argv[1], "--wrap")) {
        if (argc != 2) usage();
        return (Config){CMD_PARSE, true, true, 0, 0};
    }


    if (!strcmp(argv[1], "cmp")) {
        if (argc != 4) usage();
        return (Config){CMD_CMP, false, false, argv[2], argv[3]};
    }

    Config c = {CMD_PARSE, true, false, 0, 0};

    if (!strcmp(argv[1], "lex"))        c.cmd=CMD_LEX;
    else if (!strcmp(argv[1], "nest"))  c.cmd=CMD_NEST;
    else if (!strcmp(argv[1], "split")) c.cmd=CMD_SPLIT;
    else if (!strcmp(argv[1], "quip"))  c.cmd=CMD_QUIP;
    else if (!strcmp(argv[1], "parse")) c.cmd=CMD_PARSE;
    else usage();

    if (argc == 3) {
        if (strcmp(argv[2], "--no-color")) usage();
        c.color=0;
    }

    return c;
}



// Lexemes /////////////////////////////////////////////////////////////////////

#undef EOF

typedef enum token_type {
    BAD, EOL, EOB, EOF,
    WYTE,
    BEGIN, END,
    RUNE, WORD, TRAD, QUIP, UGLY, SLUG
} TokenType;

typedef struct { TokenType ty; char *buf; int col, sz; bool clump; } Token;

static inline Token TOK(TokenType ty, char *buf, int sz, int col, bool clump) {
    return (Token){.ty=ty, .buf=buf, .sz=sz, .col=col, .clump=clump};
}


// Rex /////////////////////////////////////////////////////////////////////////

// word       WORD
// 'quip      QUIP
// "trad"     TRAD
// ''ugly''   UGLY
// ' slug     SLUG
// (. 3 4)    BASE
// :x         PREFIX WORD
// :3.4       PREFIX TIGHT
// :(3 . 4)   PREFIX INFIX
// :(. 3 4)   PREFIX BASE

typedef enum rex_type {
    REX_WORD, REX_TRAD, REX_QUIP, REX_UGLY, REX_SLUG,
    REX_HEIR,
    CLEAR_PREFIX, CLEAR_INFIX,
    PAREN_PREFIX, PAREN_INFIX,
    CURLY_PREFIX, CURLY_INFIX,
    BRACK_PREFIX, BRACK_INFIX,
    TIGHT_PREFIX, TIGHT_INFIX,
    REX_BAD,
} RexType;

typedef struct rex_fmt {
    int  wide;   // wide output size (0 means "too big")
} RexFmt ;

typedef struct rex {
    enum rex_type t;
    char         *txt;
    int           ts;
    int           ss;
    RexFmt        fmt;
    struct rex   *rs[];
} Rex;


/// Constructing Rex ///////////////////////////////////////////////////////////

static Rex *rexNZ(enum rex_type ty, char *txt, int ts, int sons) {
    Rex *rex = malloc(sizeof(Rex) + sons*sizeof(Rex*));
    rex->t          = ty;
    rex->txt        = txt;
    rex->ts         = ts;
    rex->ss         = sons;
    rex->fmt.wide   = 0;
    return rex;
}

static Rex *rexH(Rex *hd, Rex *tl) {
    Rex *rex  = rexNZ(REX_HEIR, NULL, 0, 2);
    rex->rs[0] = hd;
    rex->rs[1] = tl;
    return rex;
}

static Rex *rexN(enum rex_type ty, char *rune, int sons) {
    return rexNZ(ty, rune, strlen(rune), sons);
}

static Rex *rex1(enum rex_type ty, char *rune, Rex *son) {
    Rex *x = rexN(ty, rune, 1);
    x->rs[0] = son;
    return x;
}

static inline int max (int a, int b) { return (a>b) ? a : b; }
static inline int min (int a, int b) { return (a<b) ? a : b; }

Rex *leaf_rex(Token tok) {
    int rty;

    switch (tok.ty) {
    case BAD:    rty=REX_BAD;  break;
    case WORD:   rty=REX_WORD; break;
    case TRAD:   rty=REX_TRAD; break;
    case QUIP:   rty=REX_QUIP; break;
    case UGLY:   rty=REX_UGLY; break;
    case SLUG:   rty=REX_SLUG; break;
    default:     die("leaf_rex: not a leaf");
    }

    int   sz  = tok.sz;
    char *p   = tok.buf;
    char *end = tok.buf+sz;
    char *out = calloc(sz+1, 1);

    int i, j, o, dsz, dent, prefix;

    switch (tok.ty) {
    case TRAD: goto trad;
    case QUIP: goto quip;
    case SLUG: goto slug;
    case UGLY: goto ugly;
    default:   goto copy;
    }

    slug:
        sz -= 2, p += 2, i=0, o=0, prefix=(tok.col + 1);
        for (; i<sz; i++,o++) {
            char c = out[o] = p[i];
            if (c == '\n') i += prefix;
        }
        sz=o;
        goto end;

  trad:
        for ( sz -= 2, p++, end--, i=0, o=0, dent=tok.col
            ; i<sz
            ; i++, o++
            )
        {
            char c = out[o] = p[i];
            if (c == '"') i++;
            if (c == '\n')
                for (int j=0; j<dent && p[i+1]==' '; j++,i++);
        }
        sz=o;
        goto end;

  quip:
        for ( sz--, p++, i=0, o=0, dent=tok.col-1
            ; i<sz
            ; i++, o++
            )
            if ((out[o]=p[i]) == '\n')
                for (int j=0; j<dent && p[i+1]==' '; j++,i++);
        sz=o;
        goto end;

  ugly:
        for (dsz=0; p[dsz] == '\''; dsz++);
        sz -= dsz*2, dent=(tok.col-1);
        if (p[dsz] == '\n') {
            for ( i=dent, o=0, p += (dsz+1), sz -= (2+dent)
                ; i<sz
                ; i++, o++
                )
                if ((out[o]=p[i]) == '\n')
                    for (j=0; j<dent && p[i+1]==' '; j++,i++);
        } else {
            for ( dent += dsz, p += dsz, i=0, o=0
                ; i<sz
                ; i++, o++
                )
                if ('\n' == (out[o] = p[i]))
                    for (j=0; j<dent && p[i+1]==' '; j++,i++);
        }
        sz=o;
        goto end;

  copy:
    memmove(out, p, sz);
    // debugf("LEAF:|%s|\n", out);

  end:
    return rexNZ(rty, out, sz, 0);
}


// Rune Precedence /////////////////////////////////////////////////////////////

static const char *runeseq = ";,:#$`~@?\\|^&=!<>+-*/%!.";

static int runeprec (char c) {
    int j=0;
    while (runeseq[j] && c != runeseq[j]) j++;
    return j;
}

static uint64_t packrune (const char *str, int sz) {
    if (sz > 13) die("can't pack wide rune");

    uint64_t place  = 1;
    uint64_t result = 0;
    for (int i=0; i<13; i++) {
        int code = i<sz ? runeprec(str[i]) : 23;
        result += place*code;
        place *= 25;
    }
    return result;
}

static int runecmp (const char *a, const char *b) {
    uint64_t aw = packrune(a, strlen(a));
    uint64_t bw = packrune(b, strlen(b));

    if (aw < bw) return -1;
    if (aw > bw) return 1;
    return 0;
}

static int runecmp_ (const void *a, const void *b) {
    return runecmp(*(const char**)a, *(const char**)b);
}

void unpack_rune (char *out, uint64_t rune) { // only needed for testing.
    for (int i=0; i<12; i++) {
        int code = rune % 25;
        out[i] = runeseq[code];
        rune = rune / 24;
    }
}

static bool isrune (char c) {
    for (int i=0; i<24; i++) if (c == runeseq[i]) return 1;
    return 0;
}



// Formatting //////////////////////////////////////////////////////////////////

/*
    Base Printer Forms

        x   -- word
        q   -- quip
        s   -- slug
        t   -- trad
        u   -- ugly
        x·y -- heir
        a+b -- infix
        +a  -- prefix
        ()  -- wrap

    When do heir elements need to be wrapped?

        These lexical comabinations can't be safely juxtaposed:

            x·x
            +·+
            ""·""
            ''x''·''x''
            'q·*        (except 'q'q and 'q''u'' and 'q' slug)

        These tree-types can't be safely juxtaposed without getting
        a different tree shape.

            a·+x    (heir becomes infix)
            a·x+y   (heir attaches to x, not x+y)
            a·(b·c) (heir order gets inverted)
            +·*     (becomes prefix BUT THIS CASE NEVER HAPPENS)
            *·+     (gets separated BUT THIS CASE NEVER HAPPENS)

        This doesn't seem like it covers everything, what are the
        other cases?

            q+   -- this one is okay.
            x+3  -- this one is okay.
            q+3  -- this just becomes a big quip.
            xq+3 -- this is a problem too.

    Which side of an heir gets the wrapping?

        If the head is a quip, always wrap the head.
        If only one side is multi-line, wrap that one.
        If only one side is long, wrap that one.
        Otherwise, wrap the right one.

    What if we ask the opposite question?


When is it safe to unwrap a node?

    First, here is a concice notation for the node types.

        x q s t u ab a+b +a (a) (+ a b) (a + b)

    And these mean:

        |  w WORD  |  ab      JUXT "juxtaposed with"  |
        |  t TEXT  |  a+b     ROPE "tight infix"      |
        |  q QUIP  |  +a      TACK "tight prefix"     |
        |  u UGLY  |  (a + b) IFIX "nest infix"       |
        |  s SLUG  |  (+ a b) NEST "nest prefix"      |

	Rules for unwrapping within juxt form.

        ; Always unwrap isolated nodes (except for the nest forms)

        w t q u s ab a+b +a

        ; These types are paren-safe.  They can be unwrapped if juxtaposed
        ; with a wrapped form.

        w() t() --- u() --- ab()
        ()w ()t ()q ()u ()s

        ; This combinations are fully safe.  If juxtaposed, both sides
        ; may be unwrapped.

            / -w -t -q -u -s
        w-  | -- wt wq wu ws
        t-  | tw -- tq tu ts
        q-  | -- -- qq qu qs
        u-  | uw uw -- -- --
        s-  | -- -- -- -- --

        Finally, the (c) in ab(c) can be unwrapped if bc could be
        unwrapped




	Here's a compressed version of the unwrapping rules for JUXT forms:

	First, if the head of the JUXT is an JUXT (ab)c, this unwraps
	left if bc unwraps left, otherwise neither side unwraps.

	Otherwise, lookup the combination in this table.

           | -w -t -q -u -s -_
        w- | || && && && && <<
        t- | && || && && && <<
        q- | >> >> && && && --
        u- | && && || || || <<
        s- | >> >> >> >> >> --
        _- | -- -- -- -- -- --

    >> means unwrap the RHS, << the LHS, && means unwrap both, || means
    that either can be unwrapped but not both, and a blank means that
    no unwrapping is possible.

    For example, if you see (foo)(bar), you lookup ww and determine
    that must onwrap only one of the two.  But for (foo)("bar"), both
    are unwrapped.  If you see (+3)(3 + 4), that falls under __, and
    neither side unwraps.


    (a' slug
    ))( 'slug
      )


    ( ' slug
    )a"t"

    And (ab)c unwraps both ways if bc unwraps both ways.

        ab('q)

        a"t"c

        (a"t")('q)
        (ab)(cd) => ab(cd)

    ''hi''
    ''hi''('q)
    (''hi'')' slug

    Note that these rules are only about unwrapping within juxt forms,
    not within other types of forms.

    These rules do not talk about cases like this:

        (-3)(.4)+(.5)(.6)

    Or this:

        -(-3)

    How about in prefix forms?  Here, only the tail may need to be
    wrapped.

        These unwrap

            +w +t +q +u +s +3.4 +ab

        TODO: does +ab always unwrap?  If a starts with a rune, then it
        would still be wrapped as +(a)b, right?

        These remain wrapped:

            +(+3) +(+ 3 4) +(3 + 4)

    How about tight infix forms:

        Tight-infix unwraps within tight infix if the precidence is lower.

        tight-prefix never unwraps within tight infix.

        unwraps:

            w+w+w
            t+t+t
            u+u+u
            ab+ab+ab

        does not unwrap:

            +'foo
            'q+(non-quip)

        x q s t u ab a+b +a (a) (+ a b) (a + b)

        These unwrap:

            w+w "t"+"t" 'q+'q 'q+''ugly'' 'q+' slug ...TODO

        These remain wrapped:

            ('q)+w (s)+w
*/


/*
           | -w -t -q -u -s -_
        w- | || && && && && <<
        t- | && || && && && <<
        q- | >> >> && && && --
        u- | && && || || || <<
        s- | >> >> >> >> >> --
        _- | -- -- -- -- -- --
*/

static FILE *rf = NULL;
static int   rd = 0;
void prex (Rex *r);
void pwrapped (Rex *r);

Rex *trailing (Rex *x) {
  loop:
    if (x->t == TIGHT_INFIX) { x = x->rs[x->ss-1]; goto loop; }
    if (x->t == REX_HEIR)    { x = x->rs[1];       goto loop; }
    return x;
}

Rex *leading (Rex *x) {
  loop:
    if (x->t == TIGHT_INFIX) { x = x->rs[0]; goto loop; }
    if (x->t == REX_HEIR)    { x = x->rs[0]; goto loop; }
    return x;
}

static bool trailing_rune (Rex *x) {
    x = trailing(x);
    return ( x->t == REX_QUIP &&
             isrune(x->txt[x->ts - 1])); }

static bool leading_tick  (Rex *x) {
    x = leading(x);
    return ( ( x->t == REX_QUIP ||
               x->t == REX_SLUG ||
               x->t == REX_UGLY )); }

static bool trailing_quip (Rex *x) { return (trailing(x)->t == REX_QUIP); }
static bool trailing_slug (Rex *x) { return (trailing(x)->t == REX_SLUG); }

static void frex(Rex *r) {
    Rex **sons = r->rs;
    int ss = r->ss;
    for (int i=0; i<r->ss; i++) frex(sons[i]);

    switch (r->t) {
    case CURLY_PREFIX:
    case BRACK_PREFIX:
    case CLEAR_PREFIX:
    case PAREN_PREFIX:
    case CURLY_INFIX:
    case BRACK_INFIX:
    case CLEAR_INFIX:
    case PAREN_INFIX: {
        int w = 3 + r->ts;  // parens + space + rune
        for (int i=0; i<ss; i++) {
            Rex *s = sons[i];
            w += 1 + s->fmt.wide;
            if (s->fmt.wide == 0) { w+=40; }
        }
        r->fmt.wide = (w>40) ? 0 : w;
        break;
    }

    case TIGHT_INFIX: {
        uint64_t or = packrune(r->txt, r->ts);
        if (ss < 2) { r->t = PAREN_PREFIX; frex(r); }
        int w=0;
        Rex *next = NULL;
        for (int i=(ss-1); i>=0; i--) {
            Rex *s = sons[i];
            { w += s->fmt.wide ? s->fmt.wide : 40;
              if (next) w += r->ts;
            }
            bool u = true;
            if (!s->fmt.wide)                                         u=0;
            if (s->t == TIGHT_INFIX && packrune(s->txt, s->ts) <= or) u=0;
            if (s->t == TIGHT_PREFIX)                                 u=0;
            if (next && trailing_rune(s))                             u=0;
            if (next && trailing_slug(s))                             u=0;
            if (next && trailing_quip(s) && !leading_tick(next))      u=0;
            if (!u) w += 2;
            next = s;
        }
        r->fmt.wide = (w>40) ? 0 : w;
        break;
    }

    case TIGHT_PREFIX: {
        if (ss != 1) { r->t=PAREN_PREFIX; return frex(r); }

        int wd = sons[0]->fmt.wide;
        if (wd) wd += strlen(r->txt);
        r->fmt.wide = wd;

        break;
    }

    case REX_WORD:
        r->fmt.wide = r->ts;
        break;

    case REX_TRAD:
        r->fmt.wide = r->ts; // TODO: escaping
        break;

    case REX_HEIR:
        // TODO: add a special-case where prefix forms are rendered as {}
        // or [].

        Rex *hd = sons[0];
        Rex *tl = sons[1];

        {
            int wd = 0;
            int hw = hd->fmt.wide, tw = tl->fmt.wide;
            if (hw && tw) {
                wd = hw+tw;
            }
            if (wd>40) wd=0;
            r->fmt.wide = wd;
            break;
        }

    // TODO: Tight Infix
    // TODO: Tight Prefix
    default:
    }
}

// Printing ////////////////////////////////////////////////////////////////////

static void red      (FILE *f) { if (conf.color) fprintf(f, "\033[1;31m");     }
static void blue     (FILE *f) { if (conf.color) fprintf(f, "\033[1;34m");     }
static void cyan     (FILE *f) { if (conf.color) fprintf(f, "\033[1;36m");     }
static void yellow   (FILE *f) { if (conf.color) fprintf(f, "\033[1;33m");     }
static void gold     (FILE *f) { if (conf.color) fprintf(f, "\033[38;5;178m"); }
static void magenta  (FILE *f) { if (conf.color) fprintf(f, "\033[1;35m");     }
static void gray     (FILE *f) { if (conf.color) fprintf(f, "\033[1;90m");     }
static void graybg   (FILE *f) { if (conf.color) fprintf(f, "\033[100m");      }
static void bluebg   (FILE *f) { if (conf.color) fprintf(f, "\033[44m");       }
// tic void redbg    (FILE *f) { if (conf.color) fprintf(f, "\033[41m");       }
static void green    (FILE *f) { if (conf.color) fprintf(f, "\033[1;32m");     }
static void bold     (FILE *f) { if (conf.color) fprintf(f, "\033[1m");        }
static void reset    (FILE *f) { if (conf.color) fprintf(f, "\033[0m");        }

static int w_col = 0;
static int w_depth = 0;

static void align () {
    for (; w_col<w_depth; w_col++) fputc(' ', rf);
}

static void wchar (char c)  { align(); fputc(c, rf); w_col++;    }
static void wstr  (char *s) { align(); while (*s) wchar(*(s++)); }
static void wgap  (void)    { align(); wchar(' ');               }
static void wline ()        { wchar('\n'); w_col=0;              }

static void inline print_open_paren (void) {
    magenta(rf); wchar('('); reset(rf);
}

static void inline print_open_curl (void) {
    magenta(rf); wchar('{'); reset(rf);
}

static void inline print_open_bracket (void) {
    magenta(rf); wchar('['); reset(rf);
}

static void inline wrune (char *txt, int sz) {
    align();
    bold(rf); gold(rf); fwrite(txt, 1, sz, rf); reset(rf);
    w_col += sz;
}

static bool isCnstr (char *p, int sz) {
    if (isdigit(*p)) return 0;
    for (int i=0; i<sz; i++, p++)
        if (!isupper(*p) && !isdigit(*p)) return 0;
    return 1;
}

static bool isType (char *p, int sz) {
    if (sz < 2) return 0;
    if (!isupper(p[0]) || isupper(p[1])) return 0;
    return 1;
}

static void inline print_word (char *txt, int sz) {
    align();
    bool color = false;
    if (isCnstr(txt,sz))     { color=1; red(rf);  }
    else if (isType(txt,sz)) { color=1; blue(rf); }
    fwrite(txt, 1, sz, rf);
    if (color) reset(rf);
    w_col += sz;
}

static void inline print_quip (char *txt, int sz) {
    int d0 = w_depth;
    w_depth = max(w_depth, w_col);
    cyan(rf);
    if (!sz) wstr("(')");
    else {
        wchar('\'');
        for (int i=0; i<sz; i++) {
            if (txt[i] == '\n') wline();
            else wchar(txt[i]);
        }
    }
    reset(rf);
    w_depth = d0;
}

static void inline print_close_paren (void) {
    magenta(rf); wchar(')'); reset(rf);
}

static void inline print_close_bracket (void) {
    magenta(rf); wchar(']'); reset(rf);
}

static void inline print_close_curl (void) {
    magenta(rf); wchar('}'); reset(rf);
}

enum cluster_elem_type { CLEM_RUNE, CLEM_REX };

typedef struct cluster_elem {
    enum cluster_elem_type ty;
    int col;
    union { Rex *rex; char *txt; };
} Clem;

static void pwrap_wide (char *az, int sz, Clem *cs) {
    if (az) { magenta(rf); wchar(az[0]); reset(rf); }

    for (int i=0; i<sz; i++) {
        Clem c = cs[i];
        if (i) wgap();
        if (c.ty == CLEM_RUNE) wrune(c.txt, strlen(c.txt));
        else pwrapped(c.rex);
    }

    if (az) { magenta(rf); wchar(az[1]); reset(rf); }
}

static void pwrap_tall (char *az, int sz, Clem *cs) {
    int d0 = w_depth;
    int d1 = max(w_col, d0);
    w_depth = d1;

    if (az) { magenta(rf); wchar(az[0]); reset(rf); }

    bool special=true; // TODO: I forget wtf is this

    for (int i=0; i < sz; i++) {
        Clem c = cs[i];

        if (i==0) {
            if (c.ty == CLEM_RUNE) {
                int rsz = strlen(c.txt);
                wrune(c.txt, rsz); wgap(); // just in case
                w_depth = d1 + (rsz + 2);
                continue;
            } else {
                w_depth = d1+2;
            }
        }

        if (c.ty == CLEM_REX) {
            if (special) { special=0; pwrapped(c.rex); }
            else { wline(); pwrapped(c.rex); }
            continue;
        }

        if (i) wgap();
        else special=1;

        wrune(c.txt, strlen(c.txt)); wgap();
    }

    if (az) {
        w_depth = d1;
        wline();
        magenta(rf); wchar(az[1]); reset(rf);
    }
    w_depth = d0;
}


/*
    (| leaf leaf leaf
      (| rex)
      leaf leaf leaf
      (| rex))

    (| a b c
      (d
        )(? (f x) x)
      leaf)
*/

/*
    printing a heir?

        (
        print head (with d = d+1)
        newline
        )
        print tail (with d = d+1)

    printing rex?

      if output col is too small?  indent

    printing a node?

      print '('
      if rune, print it

        for each son:
            if isnode?
                newline
                d = d0+2;
                print the node

            if isheir?
                newline
                print the heir

            if isleaf?
                last things was a leaf? space, otherwise newline
                print the leaf

    done?
        print ')'
*/

#define streq(a,b) (!strcmp(a,b))

static void pwrap(int w, char *az, int nc, Clem *cs) {
    if (w) pwrap_wide(az, nc, cs);
    else pwrap_tall(az, nc, cs);
}

static void prefix_wrapped (int w, char *az, char *rune, int sons, Rex **ss) {
    int nc = sons + (rune ? 1 : 0);
    Clem cs[nc];
    int o=0;

    if (rune)
        cs[o++] = (Clem){.ty = CLEM_RUNE, .col=0, .txt = rune};

    for (int i=0; i<sons; i++)
        cs[o++] = (Clem){.ty = CLEM_REX, .col=0, .rex = ss[i]};

    pwrap(w, az, nc, cs);
}

void nest_infix_tall (char *az, char *rune, int sons, Rex **ss) {
    if (!az) az = "()";
    int d0 = w_depth;
    int d1 = w_depth = max(w_depth, w_col);

    { magenta(rf); wchar(az[0]); reset(rf); }

    int rsz   = strlen(rune);
    int delem = d1 + rsz + 1;
    int drune = d1;

    // Save space by dedenting the wide runes if possible.
    if (rsz > 1 && w_depth > rsz+1) {
        drune -= rsz-1;
        delem -= rsz-1;
    }

    for (int i=0; i < sons; i++) {
        if (i) { w_depth=drune; wline(); wrune(rune, rsz); }
        w_depth=delem; pwrapped(ss[i]);
    }

    if (sons==1) {
        w_depth=drune;
        wline();
        wrune(rune, rsz);
    }

    wline();
    w_depth=d1; { magenta(rf); wchar(az[1]); reset(rf); }
    w_depth=d0;
}

void nest_infix (char *az, RexFmt fmt, char *rune, int sons, Rex **ss) {
    int w = fmt.wide;

    if (sons == 0)
        return prefix_wrapped(w, az, rune, sons, ss);

    if (!w) return nest_infix_tall(az, rune, sons, ss);

    Clem cs[sons*2];
    int o=0;

    for (int i=0; i<sons; i++) {
        cs[o++] = (Clem){.ty = CLEM_REX, .col=0, .rex = ss[i]};
        if (i == 0 || i+1 < sons)
            cs[o++] = (Clem){.ty = CLEM_RUNE, .col=0, .txt = rune};
    }

    pwrap(w, az, o, cs);
}

void pwrapped (Rex *r) {
    prex(r);
    return;
    switch (r->t) {
    case CLEAR_PREFIX:
    case PAREN_PREFIX:
    case CLEAR_INFIX:
    case PAREN_INFIX:
        prex(r); // main printer already paren-wraps.
        return;
    default:
        break;
    }

    if (r->fmt.wide) {
        prex(r);
    } else {
        print_open_paren();
        wgap();
        prex(r);
        wline();
        print_close_paren();
    }
}

int ugly_delim_size (int sz, char *b) {
    int width=1, count=0;

    for (int i=0; i<sz; i++) {
        if (b[i] == '\'') { count++; continue; }
        if (count) {
            width = max(count, width);
            count = 0;
        }
    }

    return max(count, width) + 1;
}

void prex (Rex *r) {
    if (!r) return;

    switch (r->t) {
    case REX_HEIR: {
        int d0 = w_depth;
        w_depth = max(d0, w_col);
        pwrapped(r->rs[0]);
        w_depth++;
        pwrapped(r->rs[1]);
        w_depth = d0;
        return;
    }

    case TIGHT_PREFIX:
        wrune(r->txt, r->ts);
        pwrapped(r->rs[0]);
        return;

    case CURLY_INFIX:
        nest_infix("{}", r->fmt, r->txt, r->ss, r->rs);
        return;

    case BRACK_INFIX:
        nest_infix("[]", r->fmt, r->txt, r->ss, r->rs);
        return;

    case CLEAR_INFIX:
        nest_infix(conf.wrap ? "()" : NULL, r->fmt, r->txt, r->ss, r->rs);
        return;

    case PAREN_INFIX:
        nest_infix("()", r->fmt, r->txt, r->ss, r->rs);
        return;

    case TIGHT_INFIX: {
        for (int i=0; i<r->ss; i++) {
            pwrapped(r->rs[i]);
            if (i+1 < r->ss) wrune(r->txt, r->ts);
        }
        return;
    }

    case CLEAR_PREFIX: {
        char *rune = r->txt;
        if (streq(rune, "▄")) rune=NULL;
        char *az = conf.wrap ? "()" : NULL;
        prefix_wrapped(r->fmt.wide, az, rune, r->ss, r->rs); // TODO
        return;
    }

    case PAREN_PREFIX: {
        char *rune = r->txt;
        if (streq(rune, "▄")) rune=NULL;
        prefix_wrapped(r->fmt.wide, "()", rune, r->ss, r->rs);
        return;
    }

    case BRACK_PREFIX: {
        char *rune = r->txt;
        if (streq(rune, "▄")) rune=NULL;
        prefix_wrapped(r->fmt.wide, "[]", rune, r->ss, r->rs);
        return;
    }

    case CURLY_PREFIX: {
        char *rune = r->txt;
        if (streq(rune, "▄")) rune=NULL;
        prefix_wrapped(r->fmt.wide, "{}", rune, r->ss, r->rs);
        return;
    }

    case REX_WORD:
        print_word(r->txt, r->ts);
        return;

    case REX_QUIP:
        print_quip(r->txt, r->ts);
        return;

    case REX_BAD:
        red(rf);
        wstr("BAD:");
        reset(rf);
        goto rexstr;

    case REX_SLUG: {
        yellow(rf);
        int d=w_depth;
        w_depth = max(d, w_col);
        int i=0;
        int remain = r->ts;

      line:
        if (!remain) { wchar('\''); wline(); return; }

        wchar('\'');
        if (r->txt[i] != '\n') wchar(' ');

        while (remain) {
            if (r->txt[i] == '\n') { wline(); i++; remain--; goto line; }
            wchar(r->txt[i]);
            i++, remain--;
        }
        reset(rf);
        w_depth=d;
        return;
    }

    case REX_TRAD:
    rexstr: {
        int d0 = w_depth;
        magenta(rf);
        wchar('"');
        w_depth = w_col;
        for (int i=0; i < r->ts; i++) {
            char c = r->txt[i];
            switch (c) {
            case '"':  wstr("\"\""); break;
            case '\n': wline();      break;
            default:   wchar(c);     break;
            }
        }
        wchar('"');
        reset(rf);
        w_depth = d0;
        return;
    }

    case REX_UGLY: {
        int d0 = w_depth;
        w_depth = max(w_depth, w_col);
        yellow(rf);
        int dw = ugly_delim_size(r->ts, r->txt);
        for (int i=0; i<dw; i++) { wchar('\''); } wline();
        for (int i=0; i<r->ts; i++) {
            if (r->txt[i] == '\n') wline();
            else wchar(r->txt[i]);
        }
        wline(); for (int i=0; i<dw; i++) { wchar('\''); }
        reset(rf);
        w_depth = d0;
        return;
    }

    default:
        wstr("<bad-rex-tag>");
    }
}

static inline void print_rex(FILE *f, Rex *r) {
    rf=stderr;
    frex(r);
    w_depth=4; w_col=0; rd=0; rf=f;
    prex(r);
}

static inline void print_rex0(FILE *f, Rex *r) {
    rf=stderr;
    frex(r);
    w_depth=0; w_col=0; rd=0; rf=f;
    prex(r);
}


// Constructing Infix/Prefix/Shut Forms ////////////////////////////////////////

static Rex *infix_recur
    (enum rex_type rty, int nRune, char **runes, Clem *buf, int off, int sz)
{
    if (sz == 1) return buf[off].rex;

    if (nRune == 0) {
        Rex *res = rexN(CLEAR_PREFIX, "▄", sz);
        for (int i=0; i<sz; i++) res->rs[i] = buf[i+off].rex;
        return res;
    }

    Rex *kids[sz];
    int nKid = 0;

    for (int i=0; sz>0; i++) {
        // find the next matching rune (or ix=sz)
        int ix = 0;
        for (; ix<sz; ix++) {
            Clem c = buf[off+ix];
            if (c.ty != CLEM_RUNE) continue;
            if (0 != strcmp(runes[0], c.txt)) continue;
            break;
        }

        // Process the section until then (dropping this rune);
        kids[nKid++] = infix_recur(rty, nRune-1, runes+1, buf, off, ix);

        // Repeat the process on everything after that rune.
        off += (ix+1);
        sz -= (ix+1);
    }

    if (nKid==1 && sz) return kids[0];

    Rex *r = rexN(rty, runes[0], nKid);
    for (int i=0; i<nKid; i++) r->rs[i] = kids[i];
    return r;
}

static Rex *infix_rex (enum rex_type rty, Clem *input, int sz) {

    // Collect all of the runes.

    char *runes[128] = {0};
    int nRune=0;

    for (int i=0; i<sz; i++) {
        if (input[i].ty != CLEM_RUNE) continue;
        runes[nRune++] = input[i].txt;
    }

    // Sort the runes by precidence and deduplicate.

    if (nRune) {
        qsort(runes, nRune, sizeof(char*), runecmp_);

        int uniq = 1;
        for (int i=1; i<nRune; i++) {
            if (0 != strcmp(runes[i], runes[i-1])) {
                runes[uniq++] = runes[i];
            }
        }
        nRune = uniq;
    }

    // Perform the actual recursive infix logic.

    return infix_recur(rty, nRune, runes, input, 0, sz);
}

RexType infix_color (char nestTy) {
    switch (nestTy) {
    case '(': return PAREN_INFIX;
    case '[': return BRACK_INFIX;
    case '{': return CURLY_INFIX;
    default:  die("impossible: bad nest tag");
    }
}

Rex *color (char nestTy, Rex *p) {
    switch (p->t) {
    case CLEAR_PREFIX:
        switch (nestTy) {
        case '(': p->t = PAREN_PREFIX; break;
        case '[': p->t = BRACK_PREFIX; break;
        case '{': p->t = CURLY_PREFIX; break;
        default:  die("impossible: bad nest tag");
        }
        return p;
    case CLEAR_INFIX:
        p->t = infix_color(nestTy);
        return p;
    default:
        switch (nestTy) {
        case '(': return rex1(PAREN_PREFIX, "▄", p);
        case '[': return rex1(BRACK_PREFIX, "▄", p);
        case '{': return rex1(CURLY_PREFIX, "▄", p);
        default:  die("bad nest");
        }
    }
}

static Rex *nest_rex_inner(Clem *es, int sz) {
    if (!sz) return rexN(CLEAR_PREFIX, "▄", 0);

    if (es->ty == CLEM_RUNE) die("nest cannot begin with a rune");
    // TODO: Isn't this impossible anyways, the open form would have
    // been closed already if it did?

    if (sz == 1) return es->rex;
    // This handles open forms: (+ x y) -> ((+ x y)) -> (+ x y)
    // But what about [x] -> x, how do we prevent that?

    return infix_rex(CLEAR_INFIX, es, sz);
}

static Rex *nest_rex (char nestTy, Clem *es, int sz) {
    return color(nestTy, nest_rex_inner(es, sz));
}

/*
    Okay, so the tricky bit is when we have things like:

    [+ 3 4]

    Then, this would naively parse as

        (brace prefix ø (clear prefix + 3 4))

    And that is nonsense, if there is a (* prefix ø (clear ...)) form,
    then the clear form can be collapsed.

    I don't really understand how this is being done new, this part of
    the code is very messy atm, seems like a WIP snapshot.
*/

static Rex *clump_rex (Clem *es, int sz) {
    if (sz < 1) die("impossible: empty clump");
    if (sz == 1) return es[0].rex;

    if (es[0].ty == CLEM_RUNE) {
        Rex *son = infix_rex(TIGHT_INFIX, es+1, sz-1);
        return rex1(TIGHT_PREFIX, es[0].txt, son);
    }

    return infix_rex(TIGHT_INFIX, es, sz);
}

static Rex *block_rex (Clem *es, int sz) {
    if (sz == 1) return es->rex;
    Rex *rex = rexN(CURLY_INFIX, ";", sz);
    for (int i=0; i<sz; i++) rex->rs[i] = es[i].rex;
    return rex;
}



/// Parsing Machine ////////////////////////////////////////////////////////////

enum cluster_ctx_type { NEST, CLUMP, POEM, BLOCK, ITEM };

typedef struct cluster_ctx {
    enum cluster_ctx_type ty;
    int pos;
    int sz;
    union { char nest; bool has_heir; };
} CCtx;

static struct cluster_elem elm_stk[1024] = {};
static struct cluster_ctx  ctx_stk[1024] = {
    (CCtx){ .ty=NEST, .pos=0, .sz=0, .nest='(' }
};

struct cluster_ctx  *ctop = ctx_stk;
struct cluster_elem *etop = elm_stk - 1;

// push an element to the element stack and grow the top-most context.
void raw_push_elem (Clem e) {
    *(++etop) = e;
    ctop->sz++;
}

static inline CCtx raw_pop_ctx (void) {
    return *(ctop--);
}

static inline void raw_push_ctx (CCtx c) {
    *(++ctop) = c;
}


// Closing Contexts ////////////////////////////////////////////////////////////

static int dd = 2;

void ddent (void) {
    if (!DEBUG) return;
    for (int i=0; i<dd; i++) {
        fputc(' ', stderr);
    }
}

static void debug_stack (char c) {
    Clem *elm = elm_stk;
    CCtx *ctx = ctx_stk;

    dd--; ddent(); dd++;
    gold(stderr);
    debugf("%c ", c);
    reset(stderr);

    for (ctx=ctx_stk, elm=elm_stk; ctx<=ctop; ctx++) {

        blue(stderr);

        char open  = '(';
        char close = ')';

        switch (ctx->ty) {
        case NEST:
            switch (ctx->nest) {
            case '(': break;
            case '[': open='['; close=']'; break;
            case '{': open='{'; close='}'; break;
            }
            break;
        case CLUMP: debugf("clump"); break;
        case POEM:  debugf("poem"); break;
        case ITEM:  debugf("item"); break;
        case BLOCK: debugf("block"); break;
        default: {
            int csz = ctop - ctx_stk;
            int esz = etop - elm_stk;
            debugf("\nctx:(sz=%d,off=%ld),elm:(sz=%d,off=%ld)\n", csz, ctx - ctx_stk, esz, elm-elm_stk);
            die("wtf??");
          }
        }

        magenta(stderr);
        debugf("%d", ctx->pos);
        reset(stderr);
        debugf("%c", open);

        for (int j=0; j<ctx->sz; j++, elm++) {
            switch(elm->ty) {
            case CLEM_RUNE: debugf("%s", elm->txt); break;
            case CLEM_REX:  print_rex0(stderr, elm->rex); break;
            default:        die("wut?");
            }
            if (j+1 < ctx->sz) debugf(" ");
        }

        debugf("%c ", close);
    }
}

void push_leaf (int, Rex*);

#define debugf(...) if (DEBUG) fprintf(stderr, __VA_ARGS__);

#define ENTER(...)            \
    if (DEBUG) {              \
        debug_stack('\\');        \
        debugf("\n");         \
        ddent();              \
        gold(stderr); debugf("\\ "); reset(stderr); \
        debugf(__VA_ARGS__);  \
        debugf("\n"); \
        dd += 2;              \
    }

#define EXIT(...)            \
    if (DEBUG) {             \
        dd -= 2;             \
        ddent();             \
        gold(stderr); debugf("/ "); reset(stderr); \
        debugf(__VA_ARGS__); \
        debugf("\n"); \
        debug_stack('/');    \
        debugf("\n");        \
    }

static void finalize_item (void) {
    ENTER("finalize_item");
    CCtx ctx = *ctop;
    int sz   = ctx.sz;
    Clem *es = (etop-sz) + 1;
    Rex *rex = nest_rex_inner(es, sz);

    etop -= sz;
    ctop--;
    raw_push_elem((Clem){ .ty=CLEM_REX, .col=ctx.pos, .rex=rex });
    EXIT("finalize_item");
}

static void finalize_nest (void) {
    ENTER("finalize_nest");
    CCtx ctx = *ctop;
    int sz   = ctx.sz;
    Clem *es = (etop-sz) + 1;
    Rex *rex = nest_rex(ctx.nest, es, sz);

    etop -= sz;
    ctop--;
    push_leaf(ctx.pos, rex);
    EXIT("finalize_nest");
}

static void finalize_clump (void) {
    ENTER("finalize_clump");
    CCtx ctx = raw_pop_ctx();
    int sz   = ctx.sz;
    Clem *es = (etop-sz) + 1;

    Rex *rex = clump_rex(es, sz);

    if (ctop->ty == POEM) ctop->has_heir = (ctx.pos == ctop->pos);

    // fprintf(stderr, "HIRE(%d,%d,%d,(poem=%d,heir=%d))\n", ctop->ty, ctop->pos, ctop->sz, ctop->ty == POEM, ctop->has_heir);

    ctop->sz++;
    etop -= sz;
    *(++etop) = (Clem){.ty=CLEM_REX, .col=ctx.pos, .rex=rex};
    EXIT("finalize_clump");
}

static void finalize_poem (void) {
    ENTER("finalize_poem");
    CCtx ctx   = *ctop;
    int sz     = ctx.sz;
    Clem *es   = (etop-sz) + 1;
    char *rune = es[0].txt;

    Rex *rex = NULL;

    if (ctx.has_heir) { // TODO: broken
        int nSons = sz-2;
        rex = rexN(CLEAR_PREFIX, rune, nSons);
        for (int i=0; i<nSons; i++) rex->rs[i] = es[i+1].rex;
        rex = rexH(rex, es[sz-1].rex);
    } else {
        int nSons = sz-1;
        rex = rexN(CLEAR_PREFIX, rune, nSons);
        for (int i=0; i<nSons; i++) rex->rs[i] = es[i+1].rex;
    }

    ctop--;
    etop -= sz;
    raw_push_elem((Clem){.ty=CLEM_REX, .col=ctx.pos, .rex=rex});

    if (ctop->ty == POEM) ctop->has_heir = (ctx.pos == ctop->pos);

    // fprintf(stderr, "HERE(%d,%d,%d,(poem=%d,heir=%d))\n", ctop->ty, ctop->pos, ctop->sz, ctop->ty == POEM, ctop->has_heir);

    EXIT("finalize_poem");
}

static void finalize_block (void) {
    ENTER("finalize_block");
    CCtx ctx = raw_pop_ctx();
    int sz   = ctx.sz;
    Clem *es = (etop-sz) + 1;

    if (!sz) goto end; // ignore empty blocks

    Rex *rex = block_rex(es, sz);

    ctop->sz++;
    etop -= sz;
    *(++etop) = (Clem){.ty=CLEM_REX, .rex=rex};
  end:
    EXIT("finalize_block");
}

static void finalize_ctx (void) {
    switch (ctop->ty) {
    case NEST:  finalize_nest();  break;
    case ITEM:  finalize_item();  break;
    case CLUMP: finalize_clump(); break;
    case POEM:  finalize_poem();  break;
    case BLOCK: finalize_block(); break;
    }
}

// Opening Contexts ////////////////////////////////////////////////////////////

void open_item (int col) {
    raw_push_ctx((CCtx){.ty=ITEM, .pos=col, .nest='(', .sz=0});
}

void layout (int col) {
    ENTER("layout(col=%d)", col);

    while ( (ctop->ty==POEM || ctop->ty==BLOCK || ctop->ty==ITEM) &&
            col < ctop->pos )
        finalize_ctx();

    if (ctop->ty==ITEM && col == ctop->pos && ctop->sz) finalize_ctx();

    if (ctop->ty==BLOCK && col >= ctop->pos) {
        ctop->pos = col;
        open_item(col);
    }


    EXIT("layout(col=%d)", col);
}

void open_clump (int col) {
    ENTER("open_clump [col=%d]", col);
    layout(col);
    if (ctop->ty == CLUMP) return;
    raw_push_ctx((CCtx){ .ty=CLUMP, .sz=0, .pos=col });
    EXIT("open_clump [col=%d]", col);
}

void open_block (int col) {
    ENTER("open_block[col=%d]", col);
    raw_push_ctx((CCtx){.ty=BLOCK, .pos=col, .sz=0});
    EXIT("open_block[col=%d]", col);
}


void open_nest (int col, char c) {
    ENTER("open_nest[col=%d]", col);
    open_clump(col);
    raw_push_ctx((CCtx){.ty=NEST, .pos=col, .nest=c, .sz=0});
    EXIT("open_nest[col=%d]", col);
}

void open_layout (int pos) {
    ENTER("open_layout[pos=%d]", pos);
    raw_push_ctx((CCtx){.ty=POEM, .pos=pos, .sz=0, .has_heir=0});
    EXIT("open_layout[pos=%d]", pos);
}


// Pushing Elements to Contexts ////////////////////////////////////////////////

void push_leaf (int col, Rex *rex) {
    ENTER("push_leaf[col=%d]", col);
    open_clump(col);
    Clem elm = *etop;

    if (ctop->sz && elm.ty == CLEM_REX)
        etop->rex = rexH(elm.rex, rex);
    else
		raw_push_elem((Clem){ .ty=CLEM_REX, .col=col, .rex=rex });

    EXIT("push_leaf[col=%d]", col);
}

void push_rune (Token tok) {
    ENTER("push_rune");
    char *txt = strdup(tok.buf);

    if (tok.clump) {
        open_clump(tok.col);
        raw_push_elem((Clem){ .ty=CLEM_RUNE, .col=tok.col, .txt=txt });
        goto end;
    }

    if (ctop->ty==CLUMP) finalize_clump();

    int pos = (tok.col - 1) + strlen(txt);

    layout(pos);

    // If this can be treated as an infix rune in a nest context, then
    // just push the rune.  Otherwise, we treat the rune as the beginning
    // of a new layout context.

    CCtx c = *ctop;
    if (c.ty==BLOCK || c.ty==POEM || c.sz==0 || etop->ty==CLEM_RUNE)
        open_layout(pos);
    raw_push_elem((Clem){.ty=CLEM_RUNE, .col=pos, .txt=txt});
  end:
    EXIT("push_rune");
}

static void finalize_parse (void) {
    if (etop < elm_stk) return; // ignore empty blocks.

    while (ctop > ctx_stk) finalize_ctx();

    Rex *rex = nest_rex_inner(elm_stk, ((etop+1) - elm_stk));

    print_rex(stdout, rex);
    printf("\n");
    if (conf.color) { graybg(stdout); printf(" "); reset(stdout); }
    printf("\n");
}

static void puttok (FILE *f, Token t);

static inline int ctx_rune_count (void) {
    int n=0, sz=ctop->sz;
    for (int i=0; i<sz; i++) {
        if (etop[-i].ty == CLEM_RUNE) n++;
    }
    return n;
}

static void parse (Token tok) {
    debugf("TOK[");
    if (DEBUG) puttok(stderr, tok);
    debugf("]\n");
    ENTER("parse(col=%d)", tok.col);

    switch (tok.ty) {
    case END:
        while (ctop->ty != NEST) finalize_ctx();
        if (ctop->ty == NEST) finalize_nest();
        goto end;

    case BEGIN:
        open_nest(tok.col, tok.buf[0]);
        goto end;

    case EOL:
        if ( (ctop->ty == NEST || ctop->ty == ITEM) &&
             (ctop->sz && etop->ty == CLEM_RUNE) &&
             ctx_rune_count() == 1
           )
            open_block(1 + etop[1 - ctop->sz].col);

    case WYTE:
        if (ctop->ty==CLUMP) finalize_clump();
        goto end;

    case EOF: case EOB:
        finalize_parse();
        etop = elm_stk - 1;
        ctop = ctx_stk;
        ctop->sz = 0;
        goto end;

    case RUNE:
        push_rune(tok);
        goto end;

    case BAD: case WORD: case TRAD: case QUIP: case UGLY: case SLUG:
        layout(tok.col);
        tok.buf[tok.sz] = 0;
        Rex *rex = leaf_rex(tok);
        push_leaf(tok.col, rex);
        goto end;

    default:
        die("impossible: bad token");
    }

  end:
    EXIT("parse(col=%d)", tok.col);
}


// Print Tokens with Syntax Highlighting ///////////////////////////////////////

static const bool hl_showspace = 0;

static void puttok (FILE *f, Token t) {
    switch (t.ty) {
    case BEGIN: case END: magenta(f);        break;
    case RUNE:            bold(f); gold(f);  break;
    case BAD:             bold(f); gray(f);  break;
    case TRAD: case UGLY: green(f);          break;
    case SLUG:            yellow(f);         break;
    case WORD: case EOF:
        if (isCnstr(t.buf, t.sz)) { red(f);  break; }
        if (isType(t.buf, t.sz))  { blue(f); break; }
        break;
    case EOL:
        if (hl_showspace) { red(f); fprintf(f, "|EOL"); } break;
    case WYTE:
        if (hl_showspace) { graybg(f);                  } break;
    case EOB:
        bluebg(f);
        fputc(' ', f);
        reset(f);
        fputc('\n', f);
        return;
    case QUIP:
        bold(f); cyan(f); { if (t.sz==1) graybg(f); } break;
    default:
        fprintf(f, "bad token(%d)", t.ty);
        die("bad token");
    }

    fwrite(t.buf, 1, t.sz, f);
    reset(f);
}


// Convert quips to strings. ///////////////////////////////////////////////////

static void quipemit (Token t) {
    if (conf.cmd == CMD_QUIP) puttok(stdout, t); else parse(t);
}

static void quipjoin (Token t) {
    static char buf[65536]={0};
    static int n=0, sz=0, c=0, poison=0;

  again:
    if (!c && t.ty==QUIP)       goto begin;
    if (!c)                     goto pass_over;
    if (t.ty==EOF || t.ty==EOB) goto finalize;
    if (n || t.clump)           goto consume;
    if (sz==1 && t.ty == RUNE)  goto consume;
    else                        goto finalize;

  pass_over:
    quipemit(t);
    return;

  finalize:
    if (n) poison=1;
    quipemit(TOK((poison?BAD:QUIP), buf, sz, c, 1));
    n=c=0;
    goto again;

  begin:
    n = sz = poison = 0;
    c = t.col;
    goto consume;

  consume:
    if (t.ty != EOL && t.ty != WYTE && t.col < c) poison=1;

    if (t.ty == BEGIN) n++;
    if (t.ty == END)   n--;

    memcpy(buf+sz, t.buf, t.sz);
    sz += t.sz;
    return;
}


/// Splitting Blocks ///////////////////////////////////////////////////////////

enum bsplit_mode { OUTSIDE, SINGLE_LN, BLK };

static void bsplit (Token t) {
    static enum bsplit_mode mode=OUTSIDE;
    static char s[128]={0};
    static int  eol=0, nest=0;
    static bool was_rune = false;

    if (t.ty == BEGIN) {
        switch (t.buf[0]) {
        case '(': s[nest++] = ')'; break;
        case '[': s[nest++] = ']'; break;
        case '{': s[nest++] = '}'; break;
        default: die("bad BEGIN token");
        }
    }

    else if (t.ty == END) {
        if (nest && s[nest-1]==t.buf[0]) nest--;
        else t.ty = BAD;
    }

    eol = (t.ty == EOL) ? eol+1 : 0;

    if (mode == OUTSIDE) {
        mode = t.clump ? SINGLE_LN : (t.ty==RUNE ? BLK : OUTSIDE);
    } else if (mode == SINGLE_LN) {
        if (nest==0 && eol==1) {
            if (was_rune) mode=BLK;
            else t.ty=EOB, mode=OUTSIDE;
        }
    } else if (mode == BLK) {
        if (nest==0 && eol==2) { t.ty=EOB; mode=OUTSIDE; }
    }

    if (conf.cmd == CMD_SPLIT) puttok(stdout, t); else quipjoin(t);

    was_rune = (t.ty == RUNE);
}


// Lexer ///////////////////////////////////////////////////////////////////////

typedef enum lex_mode {
    BASE_MODE, // Dispatch based on first character.
    WYTE_MODE, // | +|
    RUNE_MODE, // |{:runechar:}+|
    WORD_MODE, // |{:wordchar:}+|
    TRAD_MODE, // |("[^"]*")+|
    TICK_MODE, // |'|
    UGLY_HEAD, // |''+|
    UGLY_MODE, // |''+\n.*\n *''+|
    SLUG_TEXT, // |'( .*)?$|
    SLUG_LOOK, // |'( .*)?$|
    NOTE_MODE, // |'].*|
} LexMode;

static bool isword(char c) { return (isalnum(c) || c == '_'); }

static void lexemit(Token t) {
    t.buf[t.sz] = 0;
    if (conf.cmd == CMD_LEX) puttok(stdout, t); else bsplit(t);
}

#define emit0(t,k) { lexemit(TOK(t, buf, bufsz,   tcol, k)); \
                     bufsz=0;                                \
                     mode=BASE_MODE;                         \
                     return; }                               \

#define emit1(t,k) { lexemit(TOK(t, buf, bufsz-1, tcol, k)); \
                     buf[0] = c;                             \
                     bufsz=1;                                \
                     mode=BASE_MODE;                         \
                     goto basemode; }

static char newline[2] = { '\n', 0 };
static Token eol_tok = {.ty=EOL, .buf=newline, .sz=1, .col=0};

bool clumps (int c) {
    switch (c) {
    case ' ': case '\n': case ')': case ']': case '}': return false;
    default:                                           return true;
    }
}

void lex (int c) {
    static LexMode mode=BASE_MODE;
    static int     col=0, tcol=0; // input column, token column
    static char    buf[65536];    // token text
    static int     bufsz=0;       // Width of token text
    static int     usz=0, urem=0; // Ugly-string deliminater width+remaining
    static int     ss=0;          // Slug indenting-space count.
    static bool    tterm=0;       // Trad-string lookahead.
    static bool    poison=0;      // Dedent poision for strings.
    static int     ud=0;          // Ugly-String minimum indent.

    col = (c=='\n') ? 0 : col + 1;
    buf[bufsz++]=c;

    if (c == 256) {
        if (mode != BASE_MODE) { mode=BASE_MODE; emit0(BAD,1); }
        else { emit0(EOF,0); }
    }

    switch (mode) {
    case BASE_MODE: basemode:
        poison=tterm=0, tcol=col;

        switch (c) {
        case '(': case '[': case '{': emit0(BEGIN,1);
        case ']': case ')': case '}': emit0(END,0);
        case '\'':                    mode=TICK_MODE; return;
        case '"':                     mode=TRAD_MODE; return;
        case '\n':                    emit0(EOL,0);
        default:
            if (c == '\t') { mode=WYTE_MODE; goto wytemode; }
            if (c == ' ')  { mode=WYTE_MODE; goto wytemode; }
            if (isrune(c)) { mode=RUNE_MODE; goto runemode; }
            if (isword(c)) { mode=WORD_MODE; goto wordmode; }
            emit0(BAD,1);
        }

    case WYTE_MODE: wytemode: if (c == ' ')  return; else emit1(WYTE,0);
    case WORD_MODE: wordmode: if (isword(c)) return; else emit1(WORD,1);
    case RUNE_MODE: runemode: if (isrune(c)) return; else emit1(RUNE,clumps(c));

    case NOTE_MODE:
        if (c == '\n') emit1(WYTE,0)
        return;

    case SLUG_TEXT: slugtext:
        if (c == '\n') mode=SLUG_LOOK, ss=0;
        return;

    case SLUG_LOOK:
        switch (c) {
        case ' ':  ss++; return;
        case '\'': if (col == tcol) { mode=TICK_MODE; return; }
        default:   break;
        }

        lexemit(TOK(SLUG, buf, bufsz-(ss+2), tcol, 1));
        lexemit(eol_tok);
        if (ss) { memset(buf, ' ', ss); lexemit(TOK(WYTE, buf, ss, 1, 0)); }
        { buf[0]=c, bufsz=1, mode=BASE_MODE; goto basemode; }

    case UGLY_HEAD:
        if (c == '\'') { usz++; return; }
        ud = c=='\n' ? tcol : col;
        mode=UGLY_MODE;
        return;

    case UGLY_MODE:
        if (col<ud && c!=' ' && c!='\n')   { poison=1;         }
        if (c != '\'')                     { urem=usz; return; }
        if (--urem)                        { return;           }
        if (ud==tcol && col+1 != tcol+usz) { poison=1;         }
        emit0(poison?BAD:UGLY, 1);

    case TRAD_MODE: {
        if (col<=tcol && c!=' ' && c!='\n') { poison=1;        }
        if (c == '"' && tterm)              { tterm=0; return; }
        if (c == '"')                       { tterm=1; return; }
        if (!tterm) return;
        emit1(poison?BAD:TRAD, 1);
      }

    case TICK_MODE: // tickmode:
        switch (c) {
        case ' ':  case '\n':         mode=SLUG_TEXT; goto slugtext;
        case '\'':                    usz=2; mode=UGLY_HEAD; return;
        case '}': case ']': case ')': mode=NOTE_MODE; return;
        default:                      emit1(QUIP, 1);
        }
    }
}


// CLI Tool ////////////////////////////////////////////////////////////////////

int main (int argc, char **argv) {
    conf = argparse(argc, argv);

    if (conf.cmd == CMD_CMP) {
        char *arune = conf.r1;
        char *brune = conf.r2;
        int ord = runecmp(arune, brune);
        char o = '=';
        if (ord<0) o='<';
        if (ord>0) o='>';
        printf("(%s %c %s)\n", arune, o, brune);
        return 0;
    }

    while (1) {
        char c = getchar();
        if (!feof(stdin)) { lex(c); continue; }
        lex('\n');
        lex(256);
        return 0;
    }
}
