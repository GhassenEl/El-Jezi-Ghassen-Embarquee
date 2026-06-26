/**
 * Test userspace pour /dev/eljezi_gpio (driver eljezi-gpio-kmod).
 */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int write_cmd(int fd, const char *cmd) {
  ssize_t n = write(fd, cmd, strlen(cmd));
  return (n < 0) ? -1 : 0;
}

int main(int argc, char *argv[]) {
  const char *dev = "/dev/eljezi_gpio";
  int fd = open(dev, O_RDWR);
  if (fd < 0) {
    fprintf(stderr, "open %s: %s\n", dev, strerror(errno));
    fprintf(stderr, "Chargez le module : make -C ../eljezi-gpio-kmod install\n");
    return 1;
  }

  if (argc >= 2) {
    if (write_cmd(fd, argv[1]) != 0) {
      perror("write");
      close(fd);
      return 1;
    }
  } else {
    for (int i = 0; i < 6; i++) {
      write_cmd(fd, (i % 2) ? "1" : "0");
      sleep(1);
    }
  }

  char buf[64] = {0};
  lseek(fd, 0, SEEK_SET);
  ssize_t n = read(fd, buf, sizeof(buf) - 1);
  if (n > 0)
    printf("Lecture : %s", buf);

  close(fd);
  return 0;
}
