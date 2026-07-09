// bar_rw.c
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) {
        printf("usage: %s <BDF> <offset_hex> [write_value_hex]\n", argv[0]);
        return 1;
    }

    char path[256];
    snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/resource0", argv[1]);

    int fd = open(path, O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open resource0");
        return 1;
    }

    size_t map_size = 0x10000;
    volatile uint8_t *bar = mmap(NULL, map_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (bar == MAP_FAILED) {
    }

    unsigned long off = strtoul(argv[2], NULL, 0);
    volatile uint32_t *reg = (volatile uint32_t *)(bar + off);

    if (argc == 4) {
        uint32_t val = strtoul(argv[3], NULL, 0);
        *reg = val;
        printf("WRITE BAR0[0x%lx] = 0x%08x\n", off, val);
    }

    uint32_t rd = *reg;
    printf("READ  BAR0[0x%lx] = 0x%08x\n", off, rd);

    munmap((void *)bar, map_size);
    close(fd);
    return 0;
}