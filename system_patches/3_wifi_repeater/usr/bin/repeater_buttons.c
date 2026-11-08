#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#define POWER_DEVICE "/dev/input/event0"
#define WPS_DEVICE "/dev/input/event1"
#define LONG_PRESS_SECONDS 3

struct button_device {
    const char *path;
    int fd;
};

static struct button_device devices[] = {
    { POWER_DEVICE, -1 },
    { WPS_DEVICE, -1 }
};

static int power_pressed;
static int power_handled;
static struct timespec power_down_time;

static double elapsed_seconds(const struct timespec *start,
                              const struct timespec *end)
{
    return (double)(end->tv_sec - start->tv_sec) +
           (double)(end->tv_nsec - start->tv_nsec) / 1000000000.0;
}

static void power_off(void)
{
    syslog(LOG_NOTICE, "Power button long press detected; powering off");
    sync();
    execl("/sbin/poweroff", "poweroff", (char *)NULL);
    syslog(LOG_ERR, "Unable to execute poweroff: %s", strerror(errno));
}

static void trigger_wps(void)
{
    pid_t pid = fork();

    if (pid == 0) {
        execl("/bin/busybox", "busybox", "timeout", "-t", "10",
              "hostapd_cli", "-p", "/var/run/hostapd", "-i", "wlan1",
              "wps_pbc", (char *)NULL);
        _exit(127);
    }
    if (pid < 0)
        syslog(LOG_ERR, "Unable to start WPS: %s", strerror(errno));
    else
        syslog(LOG_INFO, "WPS push-button request sent");
}

static void handle_event(const struct input_event *event)
{
    struct timespec now;

    if (event->type != EV_KEY)
        return;

    if (event->code == KEY_POWER) {
        if (event->value == 1) {
            clock_gettime(CLOCK_MONOTONIC, &power_down_time);
            power_pressed = 1;
            power_handled = 0;
        } else if (event->value == 0 && power_pressed) {
            clock_gettime(CLOCK_MONOTONIC, &now);
            if (!power_handled &&
                elapsed_seconds(&power_down_time, &now) >= LONG_PRESS_SECONDS)
                power_off();
            power_pressed = 0;
        }
    } else if (event->code == KEY_WPS_BUTTON && event->value == 1) {
        trigger_wps();
    }
}

int main(void)
{
    struct pollfd poll_fds[2];
    struct input_event event;
    struct timespec now;
    int i;

    openlog("repeater_buttons", LOG_PID, LOG_DAEMON);
    signal(SIGCHLD, SIG_IGN);
    for (i = 0; i < 2; i++)
        devices[i].fd = open(devices[i].path, O_RDONLY | O_NONBLOCK);

    for (;;) {
        for (i = 0; i < 2; i++) {
            if (devices[i].fd < 0) {
                devices[i].fd = open(devices[i].path, O_RDONLY | O_NONBLOCK);
                if (devices[i].fd < 0 && errno != ENOENT && errno != EACCES)
                    syslog(LOG_ERR, "Cannot open %s: %s", devices[i].path,
                           strerror(errno));
            }
            poll_fds[i].fd = devices[i].fd;
            poll_fds[i].events = POLLIN;
            poll_fds[i].revents = 0;
        }

        if (poll(poll_fds, 2, 250) < 0 && errno != EINTR) {
            syslog(LOG_ERR, "Button event poll failed: %s", strerror(errno));
            sleep(1);
            continue;
        }

        for (i = 0; i < 2; i++) {
            if (devices[i].fd < 0)
                continue;
            if (poll_fds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                close(devices[i].fd);
                devices[i].fd = -1;
                continue;
            }
            if ((poll_fds[i].revents & POLLIN) &&
                read(devices[i].fd, &event, sizeof(event)) == sizeof(event))
                handle_event(&event);
        }

        if (power_pressed && !power_handled) {
            clock_gettime(CLOCK_MONOTONIC, &now);
            if (elapsed_seconds(&power_down_time, &now) >= LONG_PRESS_SECONDS) {
                power_handled = 1;
                power_off();
            }
        }
    }
}
