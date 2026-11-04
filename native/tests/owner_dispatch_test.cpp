#include <atomic>
#include <cassert>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <type_traits>
#include <utility>

#define __ANDROID__ 1

static std::atomic<bool> ownerRunning{true};
static std::atomic<bool> ownerExited{false};
static std::mutex queueMutex;
static std::condition_variable posted;
static std::function<void()> queued;
static void* bridge_currentSession() { return nullptr; }
static bool bridge_isOwnerThread() { return false; }
static bool bridge_ownerThreadRunning() { return ownerRunning; }
static bool bridge_ownerThreadExited() { return ownerExited; }
struct BridgeSessionActivation {
    explicit BridgeSessionActivation(void*) {}
};

static bool bridge_postOwnerTask(std::function<void()> task) {
    std::lock_guard<std::mutex> lock(queueMutex);
    queued = std::move(task);
    posted.notify_one();
    return true;
}

#include "owner_dispatch.inc"

static void waitForPost() {
    std::unique_lock<std::mutex> lock(queueMutex);
    assert(posted.wait_for(lock, std::chrono::seconds(1), [] { return bool(queued); }));
}

int main() {
    auto stopped = std::async(std::launch::async, [] {
        try {
            bridge_runOnOwnerSync([] { return 7; });
        } catch (const std::runtime_error&) {
            return true;
        }
        return false;
    });
    waitForPost();
    // The task remains retained while teardown waits for a caller-owned lease.
    ownerRunning = false;
    ownerExited = true;
    assert(stopped.wait_for(std::chrono::seconds(1)) == std::future_status::ready);
    assert(stopped.get());
    assert(queued);
    queued = {};

    ownerRunning = true;
    ownerExited = false;
    auto stopping = std::async(std::launch::async, [] {
        int callerOwned = 42;
        return bridge_runOnOwnerSync([&] { return callerOwned; });
    });
    waitForPost();
    // A stopping owner can still execute a task that borrows caller storage.
    ownerRunning = false;
    assert(stopping.wait_for(std::chrono::milliseconds(30)) == std::future_status::timeout);
    queued();
    assert(stopping.get() == 42);
    queued = {};

    ownerRunning = true;
    auto abandoned = std::async(std::launch::async, [] {
        try {
            bridge_runOnOwnerSync([] {});
        } catch (const std::future_error&) {
            return true;
        }
        return false;
    });
    waitForPost();
    queued = {};
    assert(abandoned.wait_for(std::chrono::seconds(1)) == std::future_status::ready);
    assert(abandoned.get());
    std::puts("Owner exit releases synchronous waiters without waiting for borrowed frames");
}
