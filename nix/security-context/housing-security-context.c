// TODO: REVIEW
// housing-security-context: attach a Wayland security context to a sandboxed
// launch.
//
// Usage:
//   housing-security-context --app-id ID --runtime-dir DIR -- CMD [ARGS...]
//
// Connects to the compositor via the *current* environment, asks
// wp_security_context_manager_v1 for a restricted listening socket at
// DIR/wayland-<pid>, then execs CMD with:
//   WAYLAND_DISPLAY=<absolute restricted socket path>
//   XDG_RUNTIME_DIR=DIR
//
// The compositor stops accepting new clients on the restricted socket when
// the close-fd pipe write end is closed; the write end is inherited (no
// CLOEXEC) across exec, so the socket lives exactly as long as the launched
// process tree. (A process that *writes* to the inherited fd makes it
// readable and thereby stops new connections to its own socket -- self-DoS
// only.)
//
// Failure policy:
// - Compositor unreachable / no security-context-v1 / rejected commit:
//   fail-closed on Wayland -- WAYLAND_DISPLAY is unset (never the
//   unrestricted socket) and CMD still runs.
// - Runtime dir integrity failure (symlink, foreign owner, group/other
//   access): hard abort. DIR typically lives under world-writable /tmp; a
//   compromised dir must not be handed to the app as XDG_RUNTIME_DIR at all.
//
// The validated directory fd is pinned: the socket is bound through
// /proc/self/fd/<dirfd>/ so a post-validation swap of the directory cannot
// redirect the bind.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
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

// Open DIR refusing symlinks, and require it to be owned by us with no
// group/other access. Returns an O_CLOEXEC directory fd, or -1.
static int open_validated_dir(const char *dir) {
    int fd = open(dir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0)
        return -1;
    struct stat st;
    if (fstat(fd, &st) < 0 || st.st_uid != geteuid() ||
        (st.st_mode & 0077) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

// Exec CMD without any Wayland access. Only reached after the runtime dir
// passed validation. Never returns on success.
static int exec_fallback(char **cmd, const char *runtime_dir,
                         const char *why) {
    fprintf(stderr,
            "housing-security-context: %s; running without Wayland access\n",
            why);
    unsetenv("WAYLAND_DISPLAY");
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    execvp(cmd[0], cmd);
    fprintf(stderr, "housing-security-context: exec %s: %s\n", cmd[0],
            strerror(errno));
    return 127;
}

static int usage(void) {
    fprintf(stderr,
            "usage: housing-security-context --app-id ID --runtime-dir DIR "
            "-- CMD [ARGS...]\n");
    return 127;
}

int main(int argc, char *argv[]) {
    const char *app_id = NULL;
    const char *runtime_dir = NULL;

    int i = 1;
    for (; i < argc; i++) {
        if (strcmp(argv[i], "--app-id") == 0 && i + 1 < argc) {
            app_id = argv[++i];
        } else if (strcmp(argv[i], "--runtime-dir") == 0 && i + 1 < argc) {
            runtime_dir = argv[++i];
        } else if (strcmp(argv[i], "--") == 0) {
            i++;
            break;
        } else {
            return usage();
        }
    }
    if (app_id == NULL || runtime_dir == NULL || i >= argc)
        return usage();
    char **cmd = &argv[i];

    // Integrity first: a bad runtime dir aborts the launch outright.
    int dir_fd = open_validated_dir(runtime_dir);
    if (dir_fd < 0) {
        fprintf(stderr,
                "housing-security-context: refusing runtime dir %s: "
                "not an owned, mode-0700, non-symlink directory\n",
                runtime_dir);
        return 125;
    }

    // The app connects by full path later; it must fit sun_path.
    char sock_name[32];
    snprintf(sock_name, sizeof(sock_name), "wayland-%d", (int)getpid());
    struct sockaddr_un probe;
    char sock_path[sizeof(probe.sun_path)];
    int n = snprintf(sock_path, sizeof(sock_path), "%s/%s", runtime_dir,
                     sock_name);
    if (n < 0 || (size_t)n >= sizeof(sock_path)) {
        fprintf(stderr,
                "housing-security-context: refusing runtime dir %s: "
                "socket path exceeds sun_path\n",
                runtime_dir);
        return 125;
    }

    // Connect using the caller's WAYLAND_DISPLAY/XDG_RUNTIME_DIR, before any
    // environment redirection.
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL)
        return exec_fallback(cmd, runtime_dir, "cannot connect to compositor");

    struct wl_registry *registry = wl_display_get_registry(display);
    if (registry == NULL) {
        wl_display_disconnect(display);
        return exec_fallback(cmd, runtime_dir, "cannot get registry");
    }
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0) {
        wl_display_disconnect(display);
        return exec_fallback(cmd, runtime_dir, "registry roundtrip failed");
    }
    if (manager == NULL) {
        wl_display_disconnect(display);
        return exec_fallback(
            cmd, runtime_dir,
            "compositor does not support wp_security_context_manager_v1");
    }

    // A stale name from a recycled pid can only be a leftover of ours: the
    // directory was just validated as owned and 0700.
    unlinkat(dir_fd, sock_name, 0);

    // Bind through the pinned fd so a directory swap after validation cannot
    // redirect the socket; 0077 umask keeps the socket inode itself 0700
    // even if the directory mode ever drifts.
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    n = snprintf(addr.sun_path, sizeof(addr.sun_path), "/proc/self/fd/%d/%s",
                 dir_fd, sock_name);
    if (n < 0 || (size_t)n >= sizeof(addr.sun_path)) {
        wl_display_disconnect(display);
        return exec_fallback(cmd, runtime_dir, "pinned bind path too long");
    }

    int listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    mode_t old_umask = umask(0077);
    int bind_ok = listen_fd >= 0 &&
                  bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) ==
                      0 &&
                  listen(listen_fd, 16) == 0;
    umask(old_umask);
    if (!bind_ok) {
        if (listen_fd >= 0)
            close(listen_fd);
        wl_display_disconnect(display);
        return exec_fallback(cmd, runtime_dir,
                             "cannot create listening socket");
    }

    // Read end goes to the compositor; the inherited write end (no CLOEXEC)
    // signals HUP when the whole launched process tree has exited.
    int close_fds[2];
    if (pipe2(close_fds, 0) < 0) {
        close(listen_fd);
        unlinkat(dir_fd, sock_name, 0);
        wl_display_disconnect(display);
        return exec_fallback(cmd, runtime_dir, "cannot create close-fd pipe");
    }

    struct wp_security_context_v1 *context =
        wp_security_context_manager_v1_create_listener(manager, listen_fd,
                                                       close_fds[0]);
    if (context == NULL) {
        close(listen_fd);
        close(close_fds[0]);
        close(close_fds[1]);
        unlinkat(dir_fd, sock_name, 0);
        wl_display_disconnect(display);
        return exec_fallback(cmd, runtime_dir,
                             "cannot create security context");
    }
    wp_security_context_v1_set_sandbox_engine(context, "nix-housing");
    wp_security_context_v1_set_app_id(context, app_id);
    char instance_id[32];
    snprintf(instance_id, sizeof(instance_id), "%d", (int)getpid());
    wp_security_context_v1_set_instance_id(context, instance_id);
    wp_security_context_v1_commit(context);
    wp_security_context_v1_destroy(context);

    // Flush the commit; a protocol error (e.g. rejected context) surfaces
    // here as a failed roundtrip.
    if (wl_display_roundtrip(display) < 0) {
        close(listen_fd);
        close(close_fds[0]);
        close(close_fds[1]);
        unlinkat(dir_fd, sock_name, 0);
        wl_display_disconnect(display);
        return exec_fallback(cmd, runtime_dir,
                             "security context rejected by compositor");
    }

    // The compositor holds its own duplicates of both fds now. Only the
    // pipe write end survives exec.
    close(listen_fd);
    close(close_fds[0]);
    close(dir_fd);
    wl_display_disconnect(display);

    setenv("WAYLAND_DISPLAY", sock_path, 1);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    execvp(cmd[0], cmd);
    fprintf(stderr, "housing-security-context: exec %s: %s\n", cmd[0],
            strerror(errno));
    return 127;
}
