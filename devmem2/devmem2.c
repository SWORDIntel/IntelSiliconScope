/*
 * devmem2.c: Enhanced program to read/write from/to any location in memory.
 * 
 * Original Copyright (C) 2000, Jan-Derk Bakker (jdb@lartmaker.nl)
 * Enhanced for DSMIL System - Intel Hardware Probing
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <ctype.h>
#include <termios.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <stdint.h>
#include <getopt.h>
  
#define FATAL(msg) do { \
    if (!quiet_mode) { \
        fprintf(stderr, "Error at line %d, file %s (%d) [%s]: %s\n", \
                __LINE__, __FILE__, errno, strerror(errno), (msg)); \
    } \
    exit(1); \
} while(0)
 
#define MAP_SIZE 4096UL
#define MAP_MASK (MAP_SIZE - 1)

/* Global options */
static int quiet_mode = 0;
static int verbose_mode = 0;
static int batch_mode = 0;
static int parse_mode = 0;  /* Output format optimized for parsing */
static int hex_output = 1;  /* Output in hex by default */

/* Print usage information */
void print_usage(const char *prog_name) {
    fprintf(stderr, "\nUsage: %s [OPTIONS] address [type [data]]\n\n", prog_name);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -q, --quiet          Quiet mode (minimal output)\n");
    fprintf(stderr, "  -v, --verbose        Verbose mode (detailed output)\n");
    fprintf(stderr, "  -b, --batch          Batch mode (read multiple addresses)\n");
    fprintf(stderr, "  -p, --parse          Parse-friendly output (for scripts)\n");
    fprintf(stderr, "  -r, --range START END  Read range of addresses\n");
    fprintf(stderr, "  -d, --decimal        Output in decimal instead of hex\n");
    fprintf(stderr, "  -h, --help           Show this help message\n\n");
    fprintf(stderr, "Arguments:\n");
    fprintf(stderr, "  address             Memory address to act upon (hex or decimal)\n");
    fprintf(stderr, "  type                Access operation type: [b]yte, [h]alfword, [w]ord, [d]word (64-bit)\n");
    fprintf(stderr, "  data                Data to be written (hex or decimal)\n\n");
    fprintf(stderr, "Examples:\n");
    fprintf(stderr, "  %s 0x10000000 w              # Read 32-bit word\n", prog_name);
    fprintf(stderr, "  %s 0x10000000 w 0x12345678  # Write 32-bit word\n", prog_name);
    fprintf(stderr, "  %s -r 0x10000000 0x1000000F # Read range\n", prog_name);
    fprintf(stderr, "  %s -p 0x10000000 w           # Parse-friendly output\n", prog_name);
    fprintf(stderr, "  %s -b 0x10000000 0x10000004 0x10000008  # Batch read\n\n", prog_name);
}

/* Read/write memory at specified address */
int access_memory(off_t target, int access_type, unsigned long writeval, int do_write) {
    int fd;
    void *map_base, *virt_addr;
    uint64_t read_result = 0;
    int ret = 0;

    if((fd = open("/dev/mem", O_RDWR | O_SYNC)) == -1) {
        if (!quiet_mode) {
            fprintf(stderr, "Failed to open /dev/mem: %s\n", strerror(errno));
            fprintf(stderr, "Note: This requires root privileges and /dev/mem access\n");
        }
        return -1;
    }
    
    if (verbose_mode) {
        printf("Opening /dev/mem...\n");
    }
    
    /* Map one page */
    map_base = mmap(0, MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, target & ~MAP_MASK);
    if(map_base == (void *) -1) {
        if (!quiet_mode) {
            fprintf(stderr, "Failed to map memory at 0x%lX: %s\n", (unsigned long)target, strerror(errno));
        }
        close(fd);
        return -1;
    }
    
    if (verbose_mode) {
        printf("Memory mapped at address %p (target: 0x%lX)\n", map_base, (unsigned long)target);
    }
    
    virt_addr = map_base + (target & MAP_MASK);
    
    /* Read operation */
    switch(access_type) {
        case 'b':
            read_result = *((uint8_t *) virt_addr);
            break;
        case 'h':
            read_result = *((uint16_t *) virt_addr);
            break;
        case 'w':
            read_result = *((uint32_t *) virt_addr);
            break;
        case 'd':
            read_result = *((uint64_t *) virt_addr);
            break;
        default:
            if (!quiet_mode) {
                fprintf(stderr, "Illegal data type '%c'.\n", access_type);
            }
            munmap(map_base, MAP_SIZE);
            close(fd);
            return -1;
    }
    
    /* Write operation if requested */
    if(do_write) {
        switch(access_type) {
            case 'b':
                *((uint8_t *) virt_addr) = (uint8_t)writeval;
                read_result = *((uint8_t *) virt_addr);
                break;
            case 'h':
                *((uint16_t *) virt_addr) = (uint16_t)writeval;
                read_result = *((uint16_t *) virt_addr);
                break;
            case 'w':
                *((uint32_t *) virt_addr) = (uint32_t)writeval;
                read_result = *((uint32_t *) virt_addr);
                break;
            case 'd':
                *((uint64_t *) virt_addr) = (uint64_t)writeval;
                read_result = *((uint64_t *) virt_addr);
                break;
        }
    }
    
    /* Output result */
    if (parse_mode) {
        /* Parse-friendly output for scripts */
        if (do_write) {
            printf("Written 0x%lX; Readback 0x%lX\n", (unsigned long)writeval, (unsigned long)read_result);
        } else {
            printf("Read 0x%lX\n", (unsigned long)read_result);
        }
    } else if (quiet_mode) {
        /* Minimal output */
        if (hex_output) {
            printf("0x%lX\n", (unsigned long)read_result);
        } else {
            printf("%lu\n", (unsigned long)read_result);
        }
    } else {
        /* Standard output */
        if (hex_output) {
            printf("Value at address 0x%lX (%p): 0x%lX", (unsigned long)target, virt_addr, (unsigned long)read_result);
            if (do_write) {
                printf(" (written 0x%lX)", (unsigned long)writeval);
            }
            printf("\n");
        } else {
            printf("Value at address 0x%lX (%p): %lu", (unsigned long)target, virt_addr, (unsigned long)read_result);
            if (do_write) {
                printf(" (written %lu)", (unsigned long)writeval);
            }
            printf("\n");
        }
    }
    
    if(munmap(map_base, MAP_SIZE) == -1) {
        if (!quiet_mode) {
            fprintf(stderr, "Failed to unmap memory: %s\n", strerror(errno));
        }
        ret = -1;
    }
    
    close(fd);
    return ret;
}

int main(int argc, char **argv) {
    int opt;
    int access_type = 'w';
    unsigned long writeval = 0;
    int do_write = 0;
    off_t target = 0;
    int range_mode = 0;
    off_t range_start = 0, range_end = 0;
    
    static struct option long_options[] = {
        {"quiet", no_argument, 0, 'q'},
        {"verbose", no_argument, 0, 'v'},
        {"batch", no_argument, 0, 'b'},
        {"parse", no_argument, 0, 'p'},
        {"range", required_argument, 0, 'r'},
        {"decimal", no_argument, 0, 'd'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    /* Parse options */
    while ((opt = getopt_long(argc, argv, "qvbpdr:h", long_options, NULL)) != -1) {
        switch(opt) {
            case 'q':
                quiet_mode = 1;
                break;
            case 'v':
                verbose_mode = 1;
                break;
            case 'b':
                batch_mode = 1;
                break;
            case 'p':
                parse_mode = 1;
                break;
            case 'r':
                range_mode = 1;
                range_start = strtoul(optarg, NULL, 0);
                if (optind < argc) {
                    range_end = strtoul(argv[optind], NULL, 0);
                    optind++;
                } else {
                    fprintf(stderr, "Error: --range requires START and END addresses\n");
                    print_usage(argv[0]);
                    exit(1);
                }
                break;
            case 'd':
                hex_output = 0;
                break;
            case 'h':
                print_usage(argv[0]);
                exit(0);
            default:
                print_usage(argv[0]);
                exit(1);
        }
    }
    
    /* Handle range mode */
    if (range_mode) {
        off_t addr;
        int step = 4;  /* Default to 32-bit word steps */
        
        if (range_start > range_end) {
            fprintf(stderr, "Error: START address must be <= END address\n");
            exit(1);
        }
        
        if (!quiet_mode && !parse_mode) {
            printf("Reading range 0x%lX to 0x%lX (step: %d bytes)\n", 
                   (unsigned long)range_start, (unsigned long)range_end, step);
        }
        
        for (addr = range_start; addr <= range_end; addr += step) {
            if (!quiet_mode && !parse_mode) {
                printf("Address 0x%lX: ", (unsigned long)addr);
            }
            if (access_memory(addr, access_type, 0, 0) < 0) {
                if (!quiet_mode) {
                    fprintf(stderr, "Failed to read address 0x%lX\n", (unsigned long)addr);
                }
            }
        }
        return 0;
    }
    
    /* Handle batch mode */
    if (batch_mode) {
        int i;
        if (optind >= argc) {
            fprintf(stderr, "Error: Batch mode requires at least one address\n");
            print_usage(argv[0]);
            exit(1);
        }
        
        if (optind + 1 < argc) {
            access_type = tolower(argv[optind + 1][0]);
        }
        
        for (i = optind; i < argc; i++) {
            target = strtoul(argv[i], NULL, 0);
            if (!quiet_mode && !parse_mode) {
                printf("Address 0x%lX: ", (unsigned long)target);
            }
            if (access_memory(target, access_type, 0, 0) < 0) {
                if (!quiet_mode) {
                    fprintf(stderr, "Failed to read address 0x%lX\n", (unsigned long)target);
                }
            }
        }
        return 0;
    }
    
    /* Standard mode - require address */
    if (optind >= argc) {
        fprintf(stderr, "Error: Address required\n");
        print_usage(argv[0]);
        exit(1);
    }
    
    target = strtoul(argv[optind], NULL, 0);
    
    if (optind + 1 < argc) {
        access_type = tolower(argv[optind + 1][0]);
    }
    
    if (optind + 2 < argc) {
        writeval = strtoul(argv[optind + 2], NULL, 0);
        do_write = 1;
    }
    
    if (access_memory(target, access_type, writeval, do_write) < 0) {
        exit(1);
    }
    
    return 0;
}
