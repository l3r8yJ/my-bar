#ifndef MY_BAR_ERROR_RESULT_H
#define MY_BAR_ERROR_RESULT_H

#define MUST_USE __attribute__((warn_unused_result))

typedef struct {
    int error;
    char *value;
} StringResult;

#endif
