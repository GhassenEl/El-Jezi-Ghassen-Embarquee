// SPDX-License-Identifier: GPL-2.0
/*
 * El Jezi Ghassen Embarquee — driver noyau minimal (character device).
 * Expose /dev/eljezi_gpio : lecture etat LED, ecriture ON/OFF.
 * Pedagogique : pas de GPIO materiel reel dans le module (etat en RAM).
 */
#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>

static int led_state;

static ssize_t eljezi_read(struct file *file, char __user *buf, size_t len, loff_t *off)
{
  char kbuf[32];
  int n;

  if (*off > 0)
    return 0;

  n = scnprintf(kbuf, sizeof(kbuf), "LED=%d\n", led_state);
  if (len < (size_t)n)
    n = (int)len;
  if (copy_to_user(buf, kbuf, n))
    return -EFAULT;
  *off += n;
  return n;
}

static ssize_t eljezi_write(struct file *file, const char __user *buf, size_t len, loff_t *off)
{
  char kbuf[16];
  size_t n = min(len, sizeof(kbuf) - 1);

  if (copy_from_user(kbuf, buf, n))
    return -EFAULT;
  kbuf[n] = '\0';

  if (kbuf[0] == '1' || kbuf[0] == 'O' || kbuf[0] == 'o')
    led_state = 1;
  else if (kbuf[0] == '0' || kbuf[0] == 'F' || kbuf[0] == 'f')
    led_state = 0;

  pr_info("eljezi_gpio: LED=%d\n", led_state);
  return len;
}

static const struct file_operations eljezi_fops = {
  .owner = THIS_MODULE,
  .read = eljezi_read,
  .write = eljezi_write,
};

static struct miscdevice eljezi_dev = {
  .minor = MISC_DYNAMIC_MINOR,
  .name = "eljezi_gpio",
  .fops = &eljezi_fops,
};

static int __init eljezi_gpio_init(void)
{
  led_state = 0;
  pr_info("eljezi_gpio: chargement module\n");
  return misc_register(&eljezi_dev);
}

static void __exit eljezi_gpio_exit(void)
{
  misc_deregister(&eljezi_dev);
  pr_info("eljezi_gpio: module retire\n");
}

module_init(eljezi_gpio_init);
module_exit(eljezi_gpio_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Ghassen El Jezi");
MODULE_DESCRIPTION("El Jezi GPIO character device (pedagogical)");
