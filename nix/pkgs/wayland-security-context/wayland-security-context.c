// wayland-security-context: attach a Wayland security context to a sandboxed
// launch.
//
// Usage:
//   wayland-security-context --app-id ID --socket PATH -- CMD [ARGS...]
//
// Connects to the compositor via the *current* environment, asks
// wp_security_context_manager_v1 for a restricted listening socket bound at
// PATH, then execs CMD with WAYLAND_DISPLAY=PATH.
//
// If PATH already exists the socket is reused as-is: no new context is
// created, WAYLAND_DISPLAY is pointed at it and CMD is exec'd.
//
// The compositor stops accepting new clients on the restricted socket when
// the close-fd pipe write end is closed; the write end is inherited (no
// CLOEXEC) across exec, so the socket lives exactly as long as the launched
// process tree.
//
// Failure policy: if the compositor is unreachable, lacks
// security-context-v1, or rejects the commit, fail closed on Wayland --
// WAYLAND_DISPLAY is unset (never the unrestricted socket) and CMD still runs.

#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <wayland-client.h>

#include "security-context-v1-client-protocol.h"

static struct wp_security_context_manager_v1 *manager = NULL;

static void registry_global(void *data, struct wl_registry *registry,
                            uint32_t name, const char *interface,
                            uint32_t version) {
    (void)data;
    (void)version;
    if (strcmp(interface, wp_security_context_manager_v1_interface.name) == 0) {
        manager = wl_registry_bind(
            registry, name, &wp_security_context_manager_v1_interface, 1);
    }
}

static void registry_global_remove(void *data, struct wl_registry *registry,
                                   uint32_t name) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

// Exec CMD without any Wayland access. Never returns on success.
static int exec_fallback(char **cmd, const char *why) {
    fprintf(stderr,
            "wayland-security-context: %s; running without Wayland access\n",
            why);
    unsetenv("WAYLAND_DISPLAY");
    execvp(cmd[0], cmd);
    fprintf(stderr, "wayland-security-context: exec %s: %s\n", cmd[0],
            strerror(errno));
    return 127;
}

// Exec CMD with WAYLAND_DISPLAY pointed at the restricted socket. Never
// returns on success.
static int exec_app(char **cmd, const char *socket_path) {
    setenv("WAYLAND_DISPLAY", socket_path, 1);
    execvp(cmd[0], cmd);
    fprintf(stderr, "wayland-security-context: exec %s: %s\n", cmd[0],
            strerror(errno));
    return 127;
}

static int usage(void) {
    fprintf(stderr, "usage: wayland-security-context --app-id ID --socket PATH "
                    "-- CMD [ARGS...]\n");
    return 127;
}

int main(int argc, char *argv[]) {
    const char *app_id = NULL;
    const char *socket_path = NULL;

    int i = 1;
    for (; i < argc; i++) {
        if (strcmp(argv[i], "--app-id") == 0 && i + 1 < argc) {
            app_id = argv[++i];
        } else if (strcmp(argv[i], "--socket") == 0 && i + 1 < argc) {
            socket_path = argv[++i];
        } else if (strcmp(argv[i], "--") == 0) {
            i++;
            break;
        } else {
            return usage();
        }
    }
    if (app_id == NULL || socket_path == NULL || i >= argc)
        return usage();
    char **cmd = &argv[i];

    // The app connects by full path; it must fit sun_path.
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    if (strlen(socket_path) >= sizeof(addr.sun_path)) {
        fprintf(stderr,
                "wayland-security-context: socket path %s exceeds sun_path\n",
                socket_path);
        return 125;
    }
    strcpy(addr.sun_path, socket_path);

    // Reuse an already-bound restricted socket instead of recreating it.
    struct stat st;
    if (lstat(socket_path, &st) == 0)
        return exec_app(cmd, socket_path);

    // Connect using the caller's WAYLAND_DISPLAY/XDG_RUNTIME_DIR, before any
    // environment redirection.
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL)
        return exec_fallback(cmd, "cannot connect to compositor");

    struct wl_registry *registry = wl_display_get_registry(display);
    if (registry == NULL) {
        wl_display_disconnect(display);
        return exec_fallback(cmd, "cannot get registry");
    }
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) {
        wl_display_disconnect(display);
        return exec_fallback(cmd, "registry roundtrip failed");
    }
    if (manager == NULL) {
        wl_display_disconnect(display);
        return exec_fallback(
            cmd, "compositor does not support wp_security_context_manager_v1");
    }

    int listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    mode_t old_umask = umask(0077);
    int bind_ok = listen_fd >= 0 &&
                  bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) == 0 &&
                  listen(listen_fd, 16) == 0;
    umask(old_umask);
    if (!bind_ok) {
        if (listen_fd >= 0)
            close(listen_fd);
        wl_display_disconnect(display);
        return exec_fallback(cmd, "cannot create listening socket");
    }

    // Read end goes to the compositor; the inherited write end (no CLOEXEC)
    // signals HUP when the whole launched process tree has exited.
    int close_fds[2];
    if (pipe2(close_fds, 0) < 0) {
        close(listen_fd);
        unlink(socket_path);
        wl_display_disconnect(display);
        return exec_fallback(cmd, "cannot create close-fd pipe");
    }

    struct wp_security_context_v1 *context =
        wp_security_context_manager_v1_create_listener(manager, listen_fd,
                                                       close_fds[0]);
    if (context == NULL) {
        close(listen_fd);
        close(close_fds[0]);
        close(close_fds[1]);
        unlink(socket_path);
        wl_display_disconnect(display);
        return exec_fallback(cmd, "cannot create security context");
    }
    wp_security_context_v1_set_sandbox_engine(context, "nix-housing");
    wp_security_context_v1_set_app_id(context, app_id);
    wp_security_context_v1_commit(context);
    wp_security_context_v1_destroy(context);

    // Flush the commit; a protocol error (e.g. rejected context) surfaces
    // here as a failed roundtrip.
    if (wl_display_roundtrip(display) < 0) {
        close(listen_fd);
        close(close_fds[0]);
        close(close_fds[1]);
        unlink(socket_path);
        wl_display_disconnect(display);
        return exec_fallback(cmd, "security context rejected by compositor");
    }

    // The compositor holds its own duplicates of both fds now. Only the
    // pipe write end survives exec.
    close(listen_fd);
    close(close_fds[0]);
    wl_display_disconnect(display);

    return exec_app(cmd, socket_path);
}
