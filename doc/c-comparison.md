Here's an example of what C code could look like using Rex notation.
This mostly doesn't try to take advantage of the nicer features of Rex,
and instead tries to stick as close as possible to C notation while
still being valid Rex.

```c
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int x;
    int y;
} Point;

Point *make_point(int x, int y) {
    Point *p = malloc(sizeof(Point));
    p->x = x;
    p->y = y;
    return p;
}

int distance_squared(Point *a, Point *b) {
    int dx = a->x - b->x;
    int dy = a->y - b->y;
    return dx * dx + dy * dy;
}

int main(int argc, char **argv) {
    Point *p1 = make_point(0, 0);
    Point *p2 = make_point(3, 4);

    int dist = distance_squared(p1, p2);
    printf("Distance squared: %d\n", dist);

    if (dist > 10) {
        printf("Far apart\n");
    } else {
        printf("Close together\n");
    }

    free(p1);
    free(p2);
    return 0;
}
```

And here is a variant in Rex notation:

```rex
include 'stdio.h
include 'stdlib.h

(typedef struct = Point):
    int x
    int y

Point *make_point(int x, int y):
    Point *p = malloc(sizeof(Point))
    p->x = x
    p->y = y
    return p

int distance_squared(Point *a, Point *b):
    int dx = a->x - b->x
    int dy = a->y - b->y
    return (dx * dx + dy * dy)

int main(int argc, char **argv):
    Point *p1 = make_point(0, 0)
    Point *p2 = make_point(3, 4)

    int dist = distance_squared(p1, p2)
    printf("Distance squared: %d\n", dist)

    if (dist > 10):
        printf("Far apart\n")
    else:
        printf("Close together\n")

    free(p1)
    free(p2)
    return 0
```

Key differences:

- Blocks use `:` with indentation (Python-style) instead of `{ }`.

- Semicolons are dropped; newlines separate statements.

- `#include <stdio.h>` becomes `include 'stdio.h` - a simple slug string.

- `typedef struct { ... } Point;` becomes `(typedef struct = Point):` with
  an indented block for the fields.

- `->` works as a tight infix rune for member access.

- `*p` for pointer declarations works naturally as a prefix rune.

- `**argv` works as a multi-character prefix rune.

- Infix operators like `-`, `*`, `+` work directly.
