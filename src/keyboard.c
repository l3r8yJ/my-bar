#include "modules.h"
#include <X11/XKBlib.h>
#include <string.h>

static Display *display;

void keyboard_init(void) { display = XOpenDisplay(NULL); }

json_object *keyboard_block(void)
{
    const char *label = "?";
    char *name = NULL;
    XkbStateRec state;
    if (display && XkbGetState(display, XkbUseCoreKbd, &state) == Success &&
        state.group < XkbNumKbdGroups) {
        XkbDescPtr keyboard = XkbGetMap(display, 0, XkbUseCoreKbd);
        if (keyboard) {
            if (XkbGetNames(display, XkbGroupNamesMask, keyboard) == Success && keyboard->names &&
                keyboard->names->groups[state.group] != None)
                name = XGetAtomName(display, keyboard->names->groups[state.group]);
            XkbFreeKeyboard(keyboard, XkbAllComponentsMask, True);
        }
        if (name) {
            label = name;
            if (strncmp(name, "English", 7) == 0)
                label = "EN";
            else if (strncmp(name, "Russian", 7) == 0)
                label = "RU";
        }
    }
    json_object *block = json_object_new_object();
    json_object_object_add(block, "full_text", json_object_new_string(label));
    if (name)
        XFree(name);
    return block;
}

void keyboard_close(void)
{
    if (display)
        XCloseDisplay(display);
    display = NULL;
}
