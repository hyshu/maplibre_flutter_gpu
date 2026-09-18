#pragma once

#include "../bridge_session.hpp"
#include "../bridge_camera_operation.hpp"

#include <cstdio>

namespace maplibre_bridge::camera {

#ifdef __ANDROID__
struct PendingCameraMutation {
    ~PendingCameraMutation() { complete(); }

    void complete() noexcept {
        if (!active.exchange(false, std::memory_order_acq_rel)) return;
        auto pending =
            g_pendingCameraMutations.load(std::memory_order_acquire);
        while (pending != 0 &&
               !g_pendingCameraMutations.compare_exchange_weak(
                   pending,
                   pending - 1,
                   std::memory_order_acq_rel,
                   std::memory_order_acquire)) {
        }
    }

    std::atomic<bool> active{true};
};

using PendingCameraMutationToken =
    std::shared_ptr<PendingCameraMutation>;

inline PendingCameraMutationToken beginPendingCameraMutation(
    bool tracked) {
    if (!tracked) return {};
    auto token = std::make_shared<PendingCameraMutation>();
    g_pendingCameraMutations.fetch_add(1, std::memory_order_acq_rel);
    return token;
}

inline void completePendingCameraMutation(
    const PendingCameraMutationToken& token) noexcept {
    if (token) token->complete();
}

#endif // __ANDROID__

// Android mutations wait until shallow frame leases release renderer storage.
// Returns one when the mutation completes or is accepted for deferred execution.
// Returns zero when the selected map is unavailable or execution fails.
template <typename Operation>
int runCameraMutation(
    const char* name,
    Operation&& operation,
    bool tracksCameraFrame = true) noexcept {
#ifdef __ANDROID__
    using StoredOperation = std::decay_t<Operation>;
    auto storedOperation = std::make_shared<StoredOperation>(
        std::forward<Operation>(operation));
    const auto operationName = std::string(name);
    const auto pendingToken =
        beginPendingCameraMutation(tracksCameraFrame);
    const auto performOperation =
        [storedOperation, operationName, pendingToken]() -> bool {
            bool result = false;
            try {
                if (g_map) result = (*storedOperation)();
            } catch (const std::exception& error) {
                std::printf(
                    "[MapLibre] %s failed: %s\n",
                    operationName.c_str(),
                    error.what());
                std::fflush(stdout);
            } catch (...) {
                std::printf(
                    "[MapLibre] %s failed: unknown exception\n",
                    operationName.c_str());
                std::fflush(stdout);
            }
            completePendingCameraMutation(pendingToken);
            return result;
        };
    std::function<void()> deferredTask = [performOperation] {
        (void)performOperation();
    };

    const auto deferIfBlocked = [&](const std::function<void()>& task) {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        discardUnacquiredFrameLocked();
        if (!g_asyncFrame.acquired &&
            !g_asyncFrame.rendering && !g_asyncFrame.syncFrameOpen) {
            return false;
        }
        g_mapIdle.store(false, std::memory_order_relaxed);
        g_renderDirty.store(true, std::memory_order_release);
        g_asyncFrame.renderDeferred = true;
        g_asyncFrame.deferredMutations.push_back(task);
        return true;
    };

    // A queued render holds no lease. Keep mutations in owner queue order so
    // subsequent camera queries observe them before another frame is drawn.
    if (deferIfBlocked(deferredTask)) return 1;
    try {
        const int result = bridge_runOnOwnerSync([&]() -> int {
            // Recheck on the owner thread because a queued render can publish first.
            if (deferIfBlocked(deferredTask)) return 2;
            return performOperation() ? 1 : 0;
        });
        return result != 0 ? 1 : 0;
    } catch (const std::exception& error) {
        std::printf("[MapLibre] %s failed: %s\n", name, error.what());
    } catch (...) {
        std::printf("[MapLibre] %s failed: unknown exception\n", name);
    }
    completePendingCameraMutation(pendingToken);
    std::fflush(stdout);
    return 0;
#else
    (void)tracksCameraFrame;
    return runCameraOperation(name, std::forward<Operation>(operation));
#endif
}

// Android gestures run asynchronously and retain their pending-frame token
// until execution or queue teardown. Other platforms execute synchronously.
template <typename Operation>
void postGestureOperation(const char* name, Operation&& operation) noexcept {
#ifdef __ANDROID__
    g_mapIdle.store(false, std::memory_order_relaxed);
    g_renderDirty.store(true, std::memory_order_release);
    const auto pendingToken = beginPendingCameraMutation(true);
    std::function<void()> task =
        [operation = std::forward<Operation>(operation),
         operationName = std::string(name),
         pendingToken]() mutable {
            try {
                if (g_map) operation();
            } catch (const std::exception& error) {
                std::printf(
                    "[MapLibre] %s failed: %s\n",
                    operationName.c_str(),
                    error.what());
                std::fflush(stdout);
            } catch (...) {
                std::printf(
                    "[MapLibre] %s failed: unknown exception\n",
                    operationName.c_str());
                std::fflush(stdout);
            }
            completePendingCameraMutation(pendingToken);
        };

    {
        std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
        discardUnacquiredFrameLocked();
        if (g_asyncFrame.acquired || g_asyncFrame.rendering ||
            g_asyncFrame.syncFrameOpen) {
            g_asyncFrame.deferredMutations.push_back(std::move(task));
            g_asyncFrame.renderDeferred = true;
            return;
        }
    }

    const bool posted = bridge_runOnOwnerAsync(
        [task = std::move(task)]() mutable {
            {
                std::lock_guard<std::mutex> lock(g_asyncFrame.mutex);
                discardUnacquiredFrameLocked();
                if (g_asyncFrame.acquired ||
                    g_asyncFrame.rendering || g_asyncFrame.syncFrameOpen) {
                    g_asyncFrame.deferredMutations.push_back(std::move(task));
                    g_asyncFrame.renderDeferred = true;
                    return;
                }
            }
            task();
        });
    if (!posted) {
        completePendingCameraMutation(pendingToken);
        std::printf("[MapLibre] %s rejected: owner thread unavailable\n", name);
        std::fflush(stdout);
    }
#else
    (void)name;
    try {
        bridge_runOnOwnerSync(
            [operation = std::forward<Operation>(operation)]() mutable {
                if (g_map) operation();
            });
    } catch (...) {
    }
#endif
}

} // namespace maplibre_bridge::camera
