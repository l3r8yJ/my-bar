#include "../src/modules.h"
#include <X11/XKBlib.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Model the real regression: XKB knows both groups; root properties are irrelevant. */
static unsigned char group;
static int available = 1;
static int connection;

Display *XOpenDisplay(const char *name)
{
    (void)name;
    return available ? (Display *)&connection : NULL;
}

int XCloseDisplay(Display *display)
{
    (void)display;
    return 0;
}

Status XkbGetState(Display *display, unsigned int device, XkbStatePtr state)
{
    (void)display;
    (void)device;
    state->group = group;
    return Success;
}

// X11's ABI fixes this parameter order; the test double must match it.
// NOLINTNEXTLINE(bugprone-easily-swappable-parameters)
XkbDescPtr XkbGetMap(Display *display, unsigned int which, unsigned int device)
{
    (void)display;
    (void)which;
    (void)device;
    return calloc(1, sizeof(XkbDescRec));
}

Status XkbGetNames(Display *display, unsigned int which, XkbDescPtr keyboard)
{
    (void)display;
    (void)which;
    keyboard->names = calloc(1, sizeof(XkbNamesRec));
    assert(keyboard->names);
    keyboard->names->groups[0] = 1;
    keyboard->names->groups[1] = 2;
    keyboard->names->groups[2] = 3;
    return Success;
}

char *XGetAtomName(Display *display, Atom atom)
{
    (void)display;
    const char *names[] = {"", "English (US)", "Russian", "German"};
    assert(atom < 4);
    return strdup(names[atom]);
}

void XkbFreeKeyboard(XkbDescPtr keyboard, unsigned int which, Bool all)
{
    (void)which;
    (void)all;
    free(keyboard->names);
    free(keyboard);
}

int XFree(void *memory)
{
    free(memory);
    return 0;
}

static void expect(unsigned char active_group, const char *expected)
{
    group = active_group;
    json_object *block = keyboard_block();
    json_object *text = NULL;
    assert(json_object_object_get_ex(block, "full_text", &text));
    assert(strcmp(json_object_get_string(text), expected) == 0);
    json_object_put(block);
}

int main(void)
{
    keyboard_init();
    for (int i = 0; i < 1000; ++i) {
        expect(0, "EN");
        expect(1, "RU");
        expect(2, "German");
        expect(3, "?");
        expect(4, "?");
    }
    keyboard_close();
    available = 0;
    keyboard_init();
    expect(1, "?");
    keyboard_close();
    puts("PASS: EN/RU from XKB names, other layouts, missing groups/display, repeated cleanup");
    return 0;
}
