/**
 * El Jezi Ghassen Embarquee — GPIO via libgpiod (Raspberry Pi / Linux moderne).
 * Remplace sysfs (deprecie) par gpiod_line API.
 */
#include <errno.h>
#include <gpiod.h>
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

static void usage(const char *prog) {
  fprintf(stderr, "Usage: %s <gpio_line> [chip]\n", prog);
  fprintf(stderr, "  gpio_line : numero de ligne (ex. 17 sur Pi)\n");
  fprintf(stderr, "  chip      : gpiochip (defaut gpiochip0)\n");
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    usage(argv[0]);
    return 1;
  }

  const char *chip_name = (argc >= 3) ? argv[2] : "gpiochip0";
  unsigned int offset = (unsigned int)atoi(argv[1]);

  signal(SIGINT, on_signal);
  signal(SIGTERM, on_signal);

  struct gpiod_chip *chip = gpiod_chip_open_by_name(chip_name);
  if (!chip) {
    fprintf(stderr, "gpiod_chip_open_by_name(%s): %s\n", chip_name, strerror(errno));
    return 1;
  }

  struct gpiod_line *line = gpiod_chip_get_line(chip, offset);
  if (!line) {
    fprintf(stderr, "gpiod_chip_get_line(%u): %s\n", offset, strerror(errno));
    gpiod_chip_close(chip);
    return 1;
  }

  if (gpiod_line_request_output(line, "eljezi-gpio-blink", 0) < 0) {
    fprintf(stderr, "gpiod_line_request_output: %s\n", strerror(errno));
    gpiod_chip_close(chip);
    return 1;
  }

  printf("=== El Jezi — libgpiod %s line %u ===\n", chip_name, offset);
  printf("Ctrl+C pour quitter.\n");

  int state = 0;
  while (running) {
    state = !state;
    if (gpiod_line_set_value(line, state) < 0) {
      fprintf(stderr, "gpiod_line_set_value: %s\n", strerror(errno));
      break;
    }
    sleep(1);
  }

  gpiod_line_set_value(line, 0);
  gpiod_line_release(line);
  gpiod_chip_close(chip);
  printf("GPIO liberee.\n");
  return 0;
}
