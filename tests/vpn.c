#include "../src/modules.h"

/*
 * @todo #7:60min Improve testing infrastructure and quality checks for this
 * memory-constrained bar. Evaluate a lightweight C test framework and coverage
 * tooling, migrate a representative test, and integrate both with just and CI.
 * Fail CI on test failures and agreed coverage regressions while preserving
 * warning-fatal builds, static analysis, and sanitizer checks.
 */
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <systemd/sd-bus.h>
#include <time.h>
#include <unistd.h>

static const char service[] = "org.freedesktop.NetworkManager";
static const char root[] = "/org/freedesktop/NetworkManager";
static const char active_interface[] = "org.freedesktop.NetworkManager.Connection.Active";
static int scenario;
static volatile sig_atomic_t stopping;
static char long_name[8192];

struct connection {
    const char *path;
    const char *type;
    const char *name;
    uint32_t state;
};

static const struct connection fixtures[] = {
    {"/active/one", "vpn", "office \"quoted\"", 2},
    {"/active/two", "wireguard", "wg", 2},
    {"/active/three", "tun", "tun", 2},
    {"/active/four", "802-3-ethernet", "ethernet", 2},
    {"/active/five", "vpn", "connecting", 1},
    {"/active/six", "wireguard", "disconnected", 4},
};

static void stop(int signum)
{
    (void)signum;
    stopping = 1;
}

// The sd-bus callback ABI fixes these adjacent string parameters.
// NOLINTNEXTLINE(bugprone-easily-swappable-parameters)
static int property(sd_bus *bus, const char *path, const char *interface, const char *name,
                    sd_bus_message *reply, void *userdata, sd_bus_error *error)
{
    (void)bus;
    (void)path;
    (void)interface;
    (void)error;
    if (strcmp(name, "ActiveConnections") == 0) {
        int result = sd_bus_message_open_container(reply, 'a', "o");
        for (size_t i = 0;
             result >= 0 && scenario != 1 && i < sizeof(fixtures) / sizeof(fixtures[0]); ++i) {
            result = sd_bus_message_append(reply, "o", fixtures[i].path);
            if (scenario == 3)
                break;
        }
        return result < 0 ? result : sd_bus_message_close_container(reply);
    }
    const struct connection *connection = userdata;
    if (scenario == 4) {
        const struct timespec delay = {.tv_nsec = 300000000};
        (void)nanosleep(&delay, NULL);
    }
    if (scenario == 2)
        return -ENOENT;
    if (strcmp(name, "Type") == 0)
        return sd_bus_message_append(reply, "s", connection->type);
    if (strcmp(name, "State") == 0)
        return sd_bus_message_append(reply, "u", connection->state);
    return sd_bus_message_append(reply, "s", scenario == 3 ? long_name : connection->name);
}

static const sd_bus_vtable manager_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("ActiveConnections", "ao", property, 0, 0),
    SD_BUS_VTABLE_END,
};
static const sd_bus_vtable connection_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_PROPERTY("Type", "s", property, 0, 0),
    SD_BUS_PROPERTY("Id", "s", property, 0, 0),
    SD_BUS_PROPERTY("State", "u", property, 0, 0),
    SD_BUS_VTABLE_END,
};

static int serve(int ready)
{
    sd_bus *bus = NULL;
    int result = sd_bus_open_user(&bus);
    if (result >= 0)
        result = sd_bus_add_object_vtable(bus, NULL, root, service, manager_vtable, NULL);
    for (size_t i = 0; result >= 0 && i < sizeof(fixtures) / sizeof(fixtures[0]); ++i)
        result = sd_bus_add_object_vtable(bus, NULL, fixtures[i].path, active_interface,
                                          connection_vtable, (void *)&fixtures[i]);
    if (result >= 0)
        result = sd_bus_request_name(bus, service, 0);
    struct sigaction action = {.sa_handler = stop};
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGTERM, &action, NULL) < 0 || result < 0 || write(ready, "1", 1) != 1) {
        close(ready);
        sd_bus_flush_close_unref(bus);
        return 1;
    }
    close(ready);
    while (!stopping) {
        result = sd_bus_process(bus, NULL);
        if (result < 0)
            break;
        if (result == 0) {
            result = sd_bus_wait(bus, 100000);
            if (result < 0 && result != -EINTR)
                break;
        }
    }
    sd_bus_flush_close_unref(bus);
    return stopping ? 0 : 1;
}

static void expect(const char *expected, const char *color)
{
    json_object *block = vpn_block(), *value = NULL;
    int found = json_object_object_get_ex(block, "full_text", &value);
    assert(found && strcmp(json_object_get_string(value), expected) == 0);
    found = json_object_object_get_ex(block, "color", &value);
    assert(found && strcmp(json_object_get_string(value), color) == 0);
    json_object_put(block);
}

int main(int argc, char **argv)
{
    memset(long_name, 'x', sizeof(long_name) - 1);
    if (argc == 2 && argv[1][0] >= '0' && argv[1][0] <= '4' && argv[1][1] == '\0') {
        scenario = argv[1][0] - '0';
        return serve(STDOUT_FILENO);
    }
    assert(argc == 1);
    const char *address = getenv("DBUS_SESSION_BUS_ADDRESS");
    assert(address);
    int result = setenv("DBUS_SYSTEM_BUS_ADDRESS", address, 1);
    assert(result == 0);
    char long_expected[sizeof(long_name) + 5];
    (void)snprintf(long_expected, sizeof(long_expected), "VPN: %s", long_name);
    const char *expected[] = {"VPN: office \"quoted\", wg, tun", "VPN: off", "VPN: unavailable",
                              long_expected, "VPN: unavailable"};
    vpn_init();
    expect("VPN: unavailable", "#888888");
    for (scenario = 0; scenario < 5; ++scenario) {
        int ready[2];
        result = pipe(ready);
        assert(result == 0);
        pid_t child = fork();
        assert(child >= 0);
        if (child == 0) {
            close(ready[0]);
            int redirected = dup2(ready[1], STDOUT_FILENO);
            if (redirected == -1) {
                close(ready[1]);
                _exit(127);
            }
            if (ready[1] != STDOUT_FILENO)
                close(ready[1]);
            char mode[] = {(char)('0' + scenario), '\0'};
            execl("/proc/self/exe", "test-vpn", mode, (char *)NULL);
            close(redirected);
            _exit(127);
        }
        close(ready[1]);
        char signal = 0;
        ssize_t count = read(ready[0], &signal, 1);
        close(ready[0]);
        assert(count == 1 && signal == '1');
        for (int i = 0; i < (scenario == 4 ? 1 : 20); ++i)
            expect(expected[scenario], scenario == 0 || scenario == 3 ? "#00cc66" : "#888888");
        result = kill(child, SIGTERM);
        assert(result == 0);
        int status = 0;
        pid_t waited = waitpid(child, &status, 0);
        assert(waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
    expect("VPN: unavailable", "#888888");
    vpn_close();
    (void)puts("PASS: D-Bus VPN filtering, multiple VPNs, quoted/long names, no VPN, missing "
               "properties, service recovery");
    return 0;
}
