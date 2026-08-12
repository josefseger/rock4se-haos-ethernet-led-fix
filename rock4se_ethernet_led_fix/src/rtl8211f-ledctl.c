#include <errno.h>
#include <linux/mii.h>
#include <linux/sockios.h>
#include <net/if.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>

#define RTL8211F_PHY_ID 0x001cc878u
#define PAGE_SELECT_REG 31
#define PAGE_STANDARD   0x0000
#define PAGE_LED        0x0d04
#define REG_PHY_ID1     2
#define REG_PHY_ID2     3
#define REG_LEDCR       0x10
#define REG_EEELCR      0x11

static int mdio_read(int fd, struct ifreq *ifr, int reg, uint16_t *value)
{
    struct mii_ioctl_data *mii = (struct mii_ioctl_data *)&ifr->ifr_data;
    mii->reg_num = reg;
    if (ioctl(fd, SIOCGMIIREG, ifr) < 0)
        return -1;
    *value = (uint16_t)(mii->val_out & 0xffff);
    return 0;
}

static int mdio_write(int fd, struct ifreq *ifr, int reg, uint16_t value)
{
    struct mii_ioctl_data *mii = (struct mii_ioctl_data *)&ifr->ifr_data;
    mii->reg_num = reg;
    mii->val_in = value;
    return ioctl(fd, SIOCSMIIREG, ifr);
}

static int parse_u16(const char *text, uint16_t *value)
{
    char *end = NULL;
    unsigned long v;
    errno = 0;
    v = strtoul(text, &end, 0);
    if (errno != 0 || end == text || *end != '\0' || v > 0xffff)
        return -1;
    *value = (uint16_t)v;
    return 0;
}

static int restore_page(int fd, struct ifreq *ifr, uint16_t page)
{
    if (mdio_write(fd, ifr, PAGE_SELECT_REG, page) < 0) {
        perror("restore PHY page");
        return -1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    const char *command;
    const char *ifname;
    int fd = -1;
    int rc = 1;
    struct ifreq ifr;
    struct mii_ioctl_data *mii;
    uint16_t saved_page = 0;
    uint16_t id1, id2, ledcr, eeelcr;
    uint32_t phy_id;
    uint16_t new_ledcr = 0, new_eeelcr = 0;

    if (argc < 3 || (strcmp(argv[1], "read") != 0 && strcmp(argv[1], "write") != 0)) {
        fprintf(stderr, "Usage: %s read <interface>\n", argv[0]);
        fprintf(stderr, "       %s write <interface> <LEDCR> <EEELCR>\n", argv[0]);
        return 2;
    }

    command = argv[1];
    ifname = argv[2];

    if (strcmp(command, "write") == 0) {
        if (argc != 5 || parse_u16(argv[3], &new_ledcr) < 0 || parse_u16(argv[4], &new_eeelcr) < 0) {
            fprintf(stderr, "Invalid write values. Expected 16-bit values such as 0x2f71 0x6007.\n");
            return 2;
        }
    }

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        perror("socket");
        return 1;
    }

    memset(&ifr, 0, sizeof(ifr));
    if (strlen(ifname) >= IFNAMSIZ) {
        fprintf(stderr, "Interface name too long.\n");
        goto out;
    }
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);

    mii = (struct mii_ioctl_data *)&ifr.ifr_data;
    if (ioctl(fd, SIOCGMIIPHY, &ifr) < 0) {
        perror("SIOCGMIIPHY");
        goto out;
    }

    if (mdio_read(fd, &ifr, PAGE_SELECT_REG, &saved_page) < 0) {
        perror("read PHY page");
        goto out;
    }

    if (mdio_write(fd, &ifr, PAGE_SELECT_REG, PAGE_STANDARD) < 0) {
        perror("select standard PHY page");
        goto out_restore;
    }
    if (mdio_read(fd, &ifr, REG_PHY_ID1, &id1) < 0 || mdio_read(fd, &ifr, REG_PHY_ID2, &id2) < 0) {
        perror("read PHY ID");
        goto out_restore;
    }

    phy_id = ((uint32_t)id1 << 16) | id2;
    if (phy_id != RTL8211F_PHY_ID) {
        fprintf(stderr, "Refusing access: PHY ID is 0x%08x, expected RTL8211F-VD 0x%08x.\n",
                phy_id, RTL8211F_PHY_ID);
        goto out_restore;
    }

    if (mdio_write(fd, &ifr, PAGE_SELECT_REG, PAGE_LED) < 0) {
        perror("select LED PHY page");
        goto out_restore;
    }
    if (mdio_read(fd, &ifr, REG_LEDCR, &ledcr) < 0 || mdio_read(fd, &ifr, REG_EEELCR, &eeelcr) < 0) {
        perror("read LED registers");
        goto out_restore;
    }

    if (strcmp(command, "write") == 0) {
        if (mdio_write(fd, &ifr, REG_LEDCR, new_ledcr) < 0 ||
            mdio_write(fd, &ifr, REG_EEELCR, new_eeelcr) < 0) {
            perror("write LED registers");
            goto out_restore;
        }
        if (mdio_read(fd, &ifr, REG_LEDCR, &ledcr) < 0 || mdio_read(fd, &ifr, REG_EEELCR, &eeelcr) < 0) {
            perror("verify LED registers");
            goto out_restore;
        }
        if (ledcr != new_ledcr || eeelcr != new_eeelcr) {
            fprintf(stderr, "Write verification failed: LEDCR=0x%04x EEELCR=0x%04x.\n", ledcr, eeelcr);
            goto out_restore;
        }
    }

    printf("PHY_ID=0x%08x\n", phy_id);
    printf("PHY_ADDR=%u\n", mii->phy_id);
    printf("LEDCR=0x%04x\n", ledcr);
    printf("EEELCR=0x%04x\n", eeelcr);
    rc = 0;

out_restore:
    if (restore_page(fd, &ifr, saved_page) < 0)
        rc = 1;
out:
    close(fd);
    return rc;
}
