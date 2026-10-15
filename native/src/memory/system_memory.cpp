#include "system_memory.hpp"

#include <algorithm>
#include <cstdio>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#if TARGET_OS_IPHONE
#include <os/proc.h>
#endif
#elif defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef PSAPI_VERSION
#define PSAPI_VERSION 2
#endif
#include <windows.h>
#include <psapi.h>
#elif defined(__linux__)
#include <sys/sysinfo.h>
#include <unistd.h>
#endif

namespace maplibre_bridge::memory {

uint64_t physicalMemoryBytes() noexcept {
#if defined(__APPLE__)
    uint64_t bytes = 0;
    size_t length = sizeof(bytes);
    return sysctlbyname("hw.memsize", &bytes, &length, nullptr, 0) == 0 ? bytes : 0;
#elif defined(_WIN32)
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    return GlobalMemoryStatusEx(&status) ? status.ullTotalPhys : 0;
#elif defined(__linux__)
    struct sysinfo status {};
    return sysinfo(&status) == 0 ? static_cast<uint64_t>(status.totalram) * status.mem_unit : 0;
#else
    return 0;
#endif
}

uint64_t availableMemoryBytes() noexcept {
#if defined(__APPLE__)
    vm_statistics64_data_t statistics{};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t pageSize = 0;
    const auto host = mach_host_self();
    const bool valid = host_page_size(host, &pageSize) == KERN_SUCCESS &&
                       host_statistics64(host, HOST_VM_INFO64,
                                         reinterpret_cast<host_info64_t>(&statistics), &count) == KERN_SUCCESS;
    mach_port_deallocate(mach_task_self(), host);
    uint64_t available = valid
                             ? (static_cast<uint64_t>(statistics.free_count) + statistics.inactive_count) * pageSize
                             : 0;
#if TARGET_OS_IPHONE
    if (__builtin_available(iOS 13.0, *)) {
        const uint64_t headroom = os_proc_available_memory();
        if (headroom != 0) available = available != 0 ? std::min(available, headroom) : headroom;
    }
#endif
    return available;
#elif defined(_WIN32)
    MEMORYSTATUSEX status{};
    status.dwLength = sizeof(status);
    return GlobalMemoryStatusEx(&status) ? status.ullAvailPhys : 0;
#elif defined(__linux__)
    if (FILE* file = std::fopen("/proc/meminfo", "r")) {
        char line[256];
        while (std::fgets(line, sizeof(line), file)) {
            unsigned long long kilobytes = 0;
            if (std::sscanf(line, "MemAvailable: %llu kB", &kilobytes) == 1) {
                std::fclose(file);
                return static_cast<uint64_t>(kilobytes) * 1024;
            }
        }
        std::fclose(file);
    }
    struct sysinfo status {};
    return sysinfo(&status) == 0
               ? (static_cast<uint64_t>(status.freeram) + status.bufferram) * status.mem_unit
               : 0;
#else
    return 0;
#endif
}

uint64_t memoryUsageBytes() noexcept {
#if defined(__APPLE__)
    task_vm_info_data_t info{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO,
                     reinterpret_cast<task_info_t>(&info), &count) == KERN_SUCCESS
               ? info.phys_footprint
               : 0;
#elif defined(_WIN32)
    PROCESS_MEMORY_COUNTERS info{};
    return GetProcessMemoryInfo(GetCurrentProcess(), &info, sizeof(info)) ? info.WorkingSetSize : 0;
#elif defined(__linux__)
    FILE* file = std::fopen("/proc/self/statm", "r");
    if (!file) return 0;
    unsigned long long virtualPages = 0;
    unsigned long long residentPages = 0;
    const bool valid = std::fscanf(file, "%llu %llu", &virtualPages, &residentPages) == 2;
    std::fclose(file);
    const auto pageSize = sysconf(_SC_PAGESIZE);
    return valid && pageSize > 0 ? static_cast<uint64_t>(residentPages) * static_cast<uint64_t>(pageSize) : 0;
#else
    return 0;
#endif
}

} // namespace maplibre_bridge::memory
