/**
 * El Jezi Ghassen Embarquée — Linux embarqué
 * Clignotement LED via sysfs GPIO (Raspberry Pi).
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void on_signal(int sig) {
  (void)sig;
  running = 0;
}

static int write_file(const char *path, const char *value) {
  int fd = open(path, O_WRONLY);
  if (fd < 0) {
    fprintf(stderr, "open %s: %s\n", path, strerror(errno));
    return -1;
  }
  ssize_t n = write(fd, value, strlen(value));
  close(fd);
  return (n < 0) ? -1 : 0;
}

static int export_gpio(int gpio) {
  char buf[8];
  snprintf(buf, sizeof buf, "%d", gpio);
  return write_file("/sys/class/gpio/export", buf);
}

static int unexport_gpio(int gpio) {
  char buf[8];
  snprintf(buf, sizeof buf, "%d", gpio);
  return write_file("/sys/class/gpio/unexport", buf);
}

static int set_direction(int gpio, const char *dir) {
  char path[64];
  snprintf(path, sizeof path, "/sys/class/gpio/gpio%d/direction", gpio);
  return write_file(path, dir);
}

static int set_value(int gpio, int value) {
  char path[64];
  char val[2] = { value ? '1' : '0', '\0' };
  snprintf(path, sizeof path, "/sys/class/gpio/gpio%d/value", gpio);
  return write_file(path, val);
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    fprintf(stderr, "Usage: %s <gpio_num>\n", argv[0]);
    return 1;
  }

  int gpio = atoi(argv[1]);
  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  printf("=== El Jezi Ghassen Embarquee — GPIO sysfs %d ===\n", gpio);
  printf("Ctrl+C pour quitter.\n");

  if (export_gpio(gpio) != 0) {
    /* Déjà exportée : on continue */
  }
  if (set_direction(gpio, "out") != 0) {
    return 1;
  }

  int state = 0;
  while (running) {
    state = !state;
    if (set_value(gpio, state) != 0) {
      break;
    }
  }

  set_value(gpio, 0);
  unexport_gpio(gpio);
  printf("GPIO %d libérée.\n", gpio);
  return 0;
}
