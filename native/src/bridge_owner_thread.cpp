#include "bridge_state.hpp"

#include <condition_variable>
#include <cstdio>
#include <mutex>
#include <thread>
#include <unordered_set>
#include <vector>

#include <mbgl/util/run_loop.hpp>

namespace {

class BridgeRuntime {
public:
    ~BridgeRuntime() { shutdown(); }

    void shutdown() {
        std::unique_lock<std::mutex> lock(mutex);
        if (!worker.joinable()) return;

        processExiting = true;
        stopping = true;
        try {
            if (g_run_loop) g_run_loop->stop();
        } catch (...) {
        }
        lock.unlock();
        worker.join();
    }

    bool acquire(void* session) {
        if (!session) return false;

        std::unique_lock<std::mutex> lock(mutex);
        if (processExiting) return false;
        if (sessions.contains(session)) {
            return running && !stopping;
        }
        if (running && !stopping) {
            sessions.insert(session);
            return true;
        }
        if (worker.joinable()) return false;

        sessions.insert(session);
        stopping = false;
        started = false;
        try {
            worker = std::thread([this] { run(); });
        } catch (...) {
            sessions.erase(session);
            return false;
        }

        startedCondition.wait(lock, [this] { return started; });
        if (running) return true;

        sessions.erase(session);
        lock.unlock();
        if (worker.joinable()) worker.join();
        lock.lock();
        started = false;
        stopping = false;
        return false;
    }

    void release(void* session) {
        bool shouldStop = false;
        {
            std::lock_guard<std::mutex> lock(mutex);
            sessions.erase(session);
            if (!worker.joinable() || !sessions.empty()) return;
            stopping = true;
            shouldStop = true;
            try {
                if (g_run_loop) g_run_loop->stop();
            } catch (...) {
            }
        }
        if (!shouldStop) return;

        worker.join();

        std::lock_guard<std::mutex> lock(mutex);
        started = false;
        stopping = false;
    }

    bool post(std::function<void()> task) {
        if (!task) return false;
        std::lock_guard<std::mutex> lock(mutex);
        if (!running || stopping || !g_run_loop) return false;
        try {
            g_run_loop->invoke(std::move(task));
            return true;
        } catch (...) {
            return false;
        }
    }

    bool isRunning(void* session) const {
        std::lock_guard<std::mutex> lock(mutex);
        return running && !stopping && g_run_loop != nullptr &&
               sessions.contains(session);
    }

    static bool isCurrent() {
        return isOwnerThread;
    }

private:
    void run() {
        isOwnerThread = true;

        bool runLoopCreated = false;
        try {
            auto loop = std::make_unique<mbgl::util::RunLoop>(
                mbgl::util::RunLoop::Type::New);
            {
                std::lock_guard<std::mutex> lock(mutex);
                g_run_loop = std::move(loop);
                running = true;
                started = true;
            }
            runLoopCreated = true;
            startedCondition.notify_all();

            // HTTP, timers, actor messages, and FFI work share one ordered
            // queue. MapSession activation is attached to each posted task.
            bool shouldRun = false;
            {
                std::lock_guard<std::mutex> lock(mutex);
                shouldRun = !stopping;
            }
            if (shouldRun) g_run_loop->run();
        } catch (const std::exception& error) {
            std::fprintf(
                stderr,
                "[MapLibre] Runtime RunLoop failed: %s\n",
                error.what());
            std::fflush(stderr);
            {
                std::lock_guard<std::mutex> lock(mutex);
                started = true;
            }
            startedCondition.notify_all();
        } catch (...) {
            std::fprintf(stderr, "[MapLibre] Runtime RunLoop failed\n");
            std::fflush(stderr);
            {
                std::lock_guard<std::mutex> lock(mutex);
                started = true;
            }
            startedCondition.notify_all();
        }

        std::vector<void*> abandonedSessions;
        {
            std::lock_guard<std::mutex> lock(mutex);
            running = false;
            if (!stopping || processExiting) {
                abandonedSessions.assign(sessions.begin(), sessions.end());
                sessions.clear();
            }
        }

        // Unexpected runtime exit: destroy every thread-affine Map while the
        // RunLoop and Scheduler TLS still belong to this thread.
        for (void* session : abandonedSessions) {
            BridgeSessionActivation activation(session);
            bridge_handleOwnerThreadExit();
        }

        std::unique_ptr<mbgl::util::RunLoop> loopToDestroy;
        if (runLoopCreated) {
            std::lock_guard<std::mutex> lock(mutex);
            loopToDestroy = std::move(g_run_loop);
        }
        loopToDestroy.reset();
        isOwnerThread = false;
    }

    mutable std::mutex mutex;
    std::condition_variable startedCondition;
    std::thread worker;
    std::unordered_set<void*> sessions;
    bool running = false;
    bool stopping = false;
    bool started = false;
    bool processExiting = false;

    static thread_local bool isOwnerThread;
};

thread_local bool BridgeRuntime::isOwnerThread = false;
BridgeRuntime g_runtime;

} // namespace

bool bridge_startOwnerThread() {
    return g_runtime.acquire(bridge_currentSession());
}

void bridge_stopOwnerThread() {
    g_runtime.release(bridge_currentSession());
}

void bridge_shutdownOwnerRuntime() {
    g_runtime.shutdown();
}

bool bridge_ownerThreadRunning() {
    return g_runtime.isRunning(bridge_currentSession());
}

bool bridge_isOwnerThread() {
    return BridgeRuntime::isCurrent();
}

bool bridge_postOwnerTask(std::function<void()> task) {
    return g_runtime.post(std::move(task));
}
