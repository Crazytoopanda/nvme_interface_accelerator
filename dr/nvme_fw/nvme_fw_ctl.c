// SPDX-License-Identifier: GPL-2.0
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "nvme_fw_regs.h"

static void usage(const char *prog)
{
	fprintf(stderr,
		"usage: %s [dev] <cmd> [args]\n"
		"\n"
		"dev defaults to /dev/nvme_fw0\n"
		"\n"
		"commands:\n"
		"  info\n"
		"  status\n"
		"  read <offset>\n"
		"  write <offset> <value>\n"
		"  ready <0|1>\n"
		"  pf1-msi\n  pf0-msi\n"
		"  ring-reset\n"
		"  wait-pid <pid> [timeout_ms]\n"
		"  fetch\n"
		"  complete <type> <sqid> <cid> <slot> <status> [specific]\n",
		prog);
}

static unsigned long parse_ulong(const char *s, const char *name)
{
	char *end = NULL;
	unsigned long v;

	errno = 0;
	v = strtoul(s, &end, 0);
	if (errno || !end || *end) {
		fprintf(stderr, "invalid %s: %s\n", name, s);
		exit(2);
	}
	return v;
}

static int read32_ioctl(int fd, uint32_t offset, uint32_t *value)
{
	struct nvme_fw_reg_io reg = {
		.offset = offset,
	};

	if (ioctl(fd, NVME_FW_IOC_READ32, &reg) < 0)
		return -1;
	*value = reg.value;
	return 0;
}

static int write32_ioctl(int fd, uint32_t offset, uint32_t value)
{
	struct nvme_fw_reg_io reg = {
		.offset = offset,
		.value = value,
	};

	return ioctl(fd, NVME_FW_IOC_WRITE32, &reg);
}

static void print_info(int fd)
{
	struct nvme_fw_info info;

	if (ioctl(fd, NVME_FW_IOC_GET_INFO, &info) < 0) {
		perror("GET_INFO");
		exit(1);
	}

	printf("vendor=0x%04x device=0x%04x bar=%u\n",
	       info.vendor, info.device, info.bar);
	printf("bar_start=0x%llx bar_len=0x%llx mapped_len=0x%x\n",
	       (unsigned long long)info.bar_start,
	       (unsigned long long)info.bar_len,
	       info.mapped_len);
	printf("layout=%u ring_magic=0x%08x debug_magic=0x%08x\n",
	       info.layout_version, info.ring_magic, info.debug_magic);
}

static void print_status(int fd)
{
	struct nvme_fw_ring_status st;

	if (ioctl(fd, NVME_FW_IOC_RING_STATUS, &st) < 0) {
		perror("RING_STATUS");
		exit(1);
	}

	printf("status=0x%08x info=0x%08x\n", st.status, st.info);
	printf("submit=%u doorbell=%u backpressure=%u\n",
	       st.submit_count, st.doorbell_count, st.backpressure_count);
	printf("pid_submit=%u pid_done=%u inflight=%u done_pending=%u\n",
	       st.pid_submit, st.pid_done, st.inflight, st.done_pending);
	printf("last_submit=0x%08x last_done=0x%08x done_count=%u\n",
	       st.last_submit, st.last_done, st.done_count);
	printf("pf1_msi_count=%u pf0_msi_count=%u\n",
	       st.pf1_msi_count, st.pf0_msi_count);
}

static void fetch_cmd(int fd)
{
	struct nvme_fw_cmd cmd;
	int i;

	if (ioctl(fd, NVME_FW_IOC_FETCH_CMD, &cmd) < 0) {
		perror("FETCH_CMD");
		exit(1);
	}

	printf("valid=%u qid=%u slot=%u seq=%u\n",
	       cmd.valid, cmd.qid, cmd.slot, cmd.seq);
	if (!cmd.valid)
		return;

	printf("opcode=0x%02x cid=%u\n", cmd.dword[0] & 0xff,
	       (cmd.dword[0] >> 16) & 0xffff);
	for (i = 0; i < 16; i++)
		printf("cdw%-2d=0x%08x%s", i, cmd.dword[i],
		       (i & 3) == 3 ? "\n" : " ");
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/nvme_fw0";
	const char *cmd;
	int argi = 1;
	int fd;

	if (argc < 2) {
		usage(argv[0]);
		return 2;
	}

	if (argv[argi][0] == '/') {
		dev = argv[argi++];
		if (argc <= argi) {
			usage(argv[0]);
			return 2;
		}
	}

	cmd = argv[argi++];
	fd = open(dev, O_RDWR);
	if (fd < 0) {
		perror(dev);
		return 1;
	}

	if (!strcmp(cmd, "info")) {
		print_info(fd);
	} else if (!strcmp(cmd, "status")) {
		print_status(fd);
	} else if (!strcmp(cmd, "read")) {
		uint32_t offset;
		uint32_t value;

		if (argc != argi + 1) {
			usage(argv[0]);
			return 2;
		}
		offset = (uint32_t)parse_ulong(argv[argi], "offset");
		if (read32_ioctl(fd, offset, &value) < 0) {
			perror("READ32");
			return 1;
		}
		printf("0x%05x = 0x%08x\n", offset, value);
	} else if (!strcmp(cmd, "write")) {
		uint32_t offset;
		uint32_t value;

		if (argc != argi + 2) {
			usage(argv[0]);
			return 2;
		}
		offset = (uint32_t)parse_ulong(argv[argi], "offset");
		value = (uint32_t)parse_ulong(argv[argi + 1], "value");
		if (write32_ioctl(fd, offset, value) < 0) {
			perror("WRITE32");
			return 1;
		}
	} else if (!strcmp(cmd, "ready")) {
		uint32_t value;

		if (argc != argi + 1) {
			usage(argv[0]);
			return 2;
		}
		value = parse_ulong(argv[argi], "ready") ? 0x10 : 0x0;
		if (write32_ioctl(fd, NVME_FW_REG_NVME_STATUS, value) < 0) {
			perror("ready WRITE32");
			return 1;
		}
	} else if (!strcmp(cmd, "pf1-msi")) {
		if (write32_ioctl(fd, (NVME_FW_RING_CTRL_BASE + NVME_FW_RING_PF1_MSI_COUNT), 1) < 0) {
			perror("PF1 MSI WRITE32");
			return 1;
		}
	} else if (!strcmp(cmd, "pf0-msi")) {
		if (ioctl(fd, NVME_FW_IOC_TRIGGER_PF0_MSI) < 0) {
			perror("TRIGGER_PF0_MSI");
			return 1;
		}
	} else if (!strcmp(cmd, "ring-reset")) {
		if (ioctl(fd, NVME_FW_IOC_RING_RESET) < 0) {
			perror("RING_RESET");
			return 1;
		}
	} else if (!strcmp(cmd, "wait-pid")) {
		struct nvme_fw_wait_pid wait = { 0 };

		if (argc < argi + 1 || argc > argi + 2) {
			usage(argv[0]);
			return 2;
		}
		wait.target_pid = (uint32_t)parse_ulong(argv[argi], "pid");
		wait.timeout_ms = (argc == argi + 2) ?
			(uint32_t)parse_ulong(argv[argi + 1], "timeout_ms") : 1000;
		if (ioctl(fd, NVME_FW_IOC_WAIT_PID, &wait) < 0) {
			perror("WAIT_PID");
			return 1;
		}
		printf("done_pid=%u irq_count=%u\n", wait.done_pid, wait.irq_count);
	} else if (!strcmp(cmd, "fetch")) {
		fetch_cmd(fd);
	} else if (!strcmp(cmd, "complete")) {
		struct nvme_fw_cpl cpl = { 0 };

		if (argc < argi + 5 || argc > argi + 6) {
			usage(argv[0]);
			return 2;
		}
		cpl.type = (uint8_t)parse_ulong(argv[argi], "type");
		cpl.sqid = (uint16_t)parse_ulong(argv[argi + 1], "sqid");
		cpl.cid = (uint16_t)parse_ulong(argv[argi + 2], "cid");
		cpl.slot = (uint16_t)parse_ulong(argv[argi + 3], "slot");
		cpl.status = (uint16_t)parse_ulong(argv[argi + 4], "status");
		cpl.specific = (argc == argi + 6) ?
			(uint32_t)parse_ulong(argv[argi + 5], "specific") : 0;
		if (ioctl(fd, NVME_FW_IOC_COMPLETE, &cpl) < 0) {
			perror("COMPLETE");
			return 1;
		}
	} else {
		usage(argv[0]);
		return 2;
	}

	close(fd);
	return 0;
}
