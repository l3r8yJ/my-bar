#include "modules.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;

static void stop(int signal_number)
{
    (void)signal_number;
    stopping = 1;
}

int main(int argc, char **argv)
{
    int once = argc == 2 && strcmp(argv[1], "--once") == 0;
    if (argc > 1 && !once) {
        (void)fprintf(stderr, "Usage: my-bar [--once]\n");
        return 2;
    }
    int descriptors[2];
    if (pipe(descriptors) < 0) {
        perror("my-bar: pipe");
        return 1;
    }
    pid_t child = fork();
    if (child < 0) {
        perror("my-bar: fork");
        close(descriptors[0]);
        close(descriptors[1]);
        return 1;
    }
    if (child == 0) {
        close(descriptors[0]);
        int redirected = dup2(descriptors[1], STDOUT_FILENO);
        if (redirected == -1) {
            close(descriptors[1]);
            _exit(127);
        }
        if (descriptors[1] != STDOUT_FILENO)
            close(descriptors[1]);
        execlp("i3status", "i3status", (char *)NULL);
        perror("my-bar: i3status");
        close(redirected);
        _exit(127);
    }
    close(descriptors[1]);
    struct sigaction action = {.sa_handler = stop};
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    action.sa_handler = SIG_IGN;
    sigaction(SIGPIPE, &action, NULL);
    FILE *input = fdopen(descriptors[0], "r");
    if (!input) {
        perror("my-bar: fdopen");
        close(descriptors[0]);
        kill(child, SIGTERM);
        waitpid(child, NULL, 0);
        return 1;
    }
    keyboard_init();
    vpn_init();
    if (!once)
        puts("{\"version\":1}\n[");
    char *line = NULL;
    size_t capacity = 0;
    int frames = 0, result = 0;
    while (!stopping && getline(&line, &capacity, input) >= 0) {
        char *start = line;
        while (*start == ',' || *start == ' ' || *start == '\t')
            ++start;
        if (*start == '{' || strcmp(start, "[\n") == 0)
            continue;
        json_object *source = json_tokener_parse(start);
        if (!source || !json_object_is_type(source, json_type_array)) {
            (void)fprintf(stderr, "my-bar: invalid i3status frame\n");
            json_object_put(source);
            result = 1;
            break;
        }
        json_object *output = json_object_new_array();
        json_object_array_add(output, keyboard_block());
        json_object_array_add(output, vpn_block());
        size_t count = json_object_array_length(source);
        for (size_t i = 0; i < count; ++i) {
            json_object *block = json_object_array_get_idx(source, i);
            json_object *text;
            if (!json_object_is_type(block, json_type_object) ||
                !json_object_object_get_ex(block, "full_text", &text) ||
                !json_object_is_type(text, json_type_string)) {
                result = 1;
                break;
            }
            json_object_array_add(output, json_object_get(block));
            if (i == 0)
                json_object_array_add(output, metrics_block());
        }
        if (count == 0)
            json_object_array_add(output, metrics_block());
        for (size_t i = 0; !result && i < json_object_array_length(output); ++i) {
            json_object *block = json_object_array_get_idx(output, i);
            json_object *text;
            json_object_object_get_ex(block, "full_text", &text);
            const char *value = json_object_get_string(text);
            size_t length = strlen(value);
            while (length && value[0] == ' ') {
                ++value;
                --length;
            }
            while (length && value[length - 1] == ' ')
                --length;
            char *padded = malloc(length + 3);
            if (!padded) {
                result = 1;
                break;
            }
            padded[0] = ' ';
            memcpy(padded + 1, value, length);
            padded[length + 1] = ' ';
            padded[length + 2] = '\0';
            json_object_object_add(block, "full_text", json_object_new_string(padded));
            json_object_object_add(block, "separator_block_width", json_object_new_int(1));
            free(padded);
        }
        if (!result) {
            printf("%s%s\n", frames && !once ? "," : "",
                   json_object_to_json_string_ext(output, JSON_C_TO_STRING_PLAIN));
            if (fflush(stdout) == EOF)
                result = 1;
            ++frames;
        }
        json_object_put(output);
        json_object_put(source);
        if (once || result)
            break;
    }
    if ((!frames || !once) && !stopping)
        result = 1;
    free(line);
    if (fclose(input) != 0)
        result = 1;
    kill(child, SIGTERM);
    int status;
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
    }
    vpn_close();
    keyboard_close();
    return result;
}
