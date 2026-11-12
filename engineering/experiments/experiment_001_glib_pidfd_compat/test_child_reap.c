#include <glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static GMainLoop *loop;
static int final_exit_status = -999;
static int callback_fired = 0;

static void child_watch_cb(GPid pid, gint status, gpointer user_data) {
    callback_fired = 1;
    final_exit_status = status;
    printf("[test_child_reap] Child watch callback invoked for PID %d with raw status %d\n", pid, status);
    g_spawn_close_pid(pid);
    g_main_loop_quit(loop);
}

int main(int argc, char **argv) {
    loop = g_main_loop_new(NULL, FALSE);
    char *args[] = {"/bin/true", NULL};
    GPid pid;
    GError *err = NULL;

    printf("[test_child_reap] Spawning child process: %s\n", args[0]);
    if (!g_spawn_async(NULL, args, NULL, G_SPAWN_DO_NOT_REAP_CHILD, NULL, NULL, &pid, &err)) {
        fprintf(stderr, "[test_child_reap] Spawn failed: %s\n", err->message);
        return 1;
    }

    printf("[test_child_reap] Child spawned with PID %d. Registering child watch...\n", pid);
    g_child_watch_add(pid, child_watch_cb, NULL);

    g_main_loop_run(loop);
    printf("[test_child_reap] Main loop exited.\n");

    if (!callback_fired) {
        fprintf(stderr, "[test_child_reap] ERROR: Child watch callback never fired!\n");
        return 2;
    }

    if (final_exit_status != 0) {
        fprintf(stderr, "[test_child_reap] FAILURE: Child status was %d (expected 0). Zombie / reaping failure detected!\n", final_exit_status);
        return 3;
    }

    printf("[test_child_reap] SUCCESS: Child process cleanly reaped with exit status 0.\n");
    return 0;
}
