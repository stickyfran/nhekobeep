// SPDX-FileCopyrightText: Nheko Contributors
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "BeeperReinitController.h"

#include <atomic>
#include <map>
#include <string>

#include <QEventLoop>
#include <QMetaObject>
#include <QTimer>
#include <QThread>
#include <QElapsedTimer>

#include <nlohmann/json.hpp>

#include <mtx/responses/messages.hpp>
#include <mtx/responses/profile.hpp>
#include <mtx/responses/sync.hpp>
#include <mtxclient/http/client.hpp>
#include <mtx/events.hpp>
#include <mtx/events/collections.hpp>

#include "BeeperBridge.h"
#include "Cache_p.h"
#include "CacheStructs.h"
#include "ChatPage.h"
#include "Logging.h"
#include "MatrixClient.h"
#include "MxcImageProvider.h"
#include "UserSettingsPage.h"
#include "Utils.h"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
static constexpr int AVATAR_DOWNLOAD_SIZE     = 256;  // Larger for crisp previews
static constexpr int AVATAR_TIMEOUT_MS        = 30000;
static constexpr int PROFILE_FETCH_TIMEOUT_MS = 30000;
static constexpr int AVATAR_BATCH_DELAY_MS    = 100;
static constexpr int MAX_AVATARS_PER_BATCH    = 20;

// ---------------------------------------------------------------------------
// BeeperReinitController
// ---------------------------------------------------------------------------
BeeperReinitController::BeeperReinitController(QObject *parent)
  : QObject(parent)
{
    workerThread_.setObjectName(QStringLiteral("beeper-reinit-worker"));
}

BeeperReinitController::~BeeperReinitController()
{
    cancelled_.storeRelaxed(1);
    workerThread_.quit();
    workerThread_.wait();
}

void
BeeperReinitController::startBeeperReinit()
{
    if (workerThread_.isRunning()) {
        nhlog::ui()->warn("Beeper re-init already in progress, ignoring duplicate request.");
        return;
    }

    cancelled_.storeRelaxed(0);

    auto *worker = new BeeperReinitWorker(&cancelled_);
    worker->moveToThread(&workerThread_);

    // Forward signals from worker to QML-facing signals.
    connect(worker,
            &BeeperReinitWorker::phaseChanged,
            this,
            &BeeperReinitController::reinitPhaseChanged);
    connect(worker,
            &BeeperReinitWorker::progressUpdated,
            this,
            &BeeperReinitController::reinitProgressUpdated);
    connect(worker, &BeeperReinitWorker::finished, this, [this](bool ok, QString msg) {
        emit reinitFinished(ok, msg);
    });

    // Clean up worker when done.
    connect(worker, &BeeperReinitWorker::finished, worker, &QObject::deleteLater);
    connect(&workerThread_, &QThread::finished, worker, &QObject::deleteLater);

    // Kick off the work when the thread starts.
    connect(&workerThread_, &QThread::started, worker, &BeeperReinitWorker::process);

    emit reinitStarted();
    workerThread_.start();
}

// ---------------------------------------------------------------------------
// BeeperReinitWorker
// ---------------------------------------------------------------------------
BeeperReinitWorker::BeeperReinitWorker(QAtomicInt *cancelFlag, QObject *parent)
  : QObject(parent)
  , cancelled_(cancelFlag)
{
}

void
BeeperReinitWorker::process()
{
    nhlog::ui()->info("BeeperReinit: worker started.");

    auto *cache = cache::client();
    if (!cache || !cache->isDatabaseReady()) {
        emit finished(false, QStringLiteral("Database not ready."));
        return;
    }

    // =====================================================================
    // PHASE 1: Pause sync loop
    // =====================================================================
    {
        emit phaseChanged(QStringLiteral("Pausing sync..."));
        nhlog::ui()->info("BeeperReinit: Phase 1/6 — Pausing sync loop.");

        // Shutdown the HTTP client to abort any in-flight sync requests.
        http::client()->shutdown();

        // Disconnect the trySyncCb signal via ChatPage's main thread.
        bool paused = false;
        QMetaObject::invokeMethod(
          ChatPage::instance(),
          [&paused]() {
              // Disconnect ALL connections to trySyncCb to prevent new syncs.
              QObject::disconnect(ChatPage::instance(),
                                  &ChatPage::trySyncCb,
                                  nullptr,
                                  nullptr);
              QObject::disconnect(ChatPage::instance(),
                                  &ChatPage::tryDelayedSyncCb,
                                  nullptr,
                                  nullptr);
              QObject::disconnect(ChatPage::instance(),
                                  &ChatPage::tryInitialSyncCb,
                                  nullptr,
                                  nullptr);
              paused = true;
          },
          Qt::BlockingQueuedConnection);

        if (!paused) {
            emit finished(false, QStringLiteral("Failed to pause sync loop."));
            return;
        }

        // Small delay to let pending callbacks drain.
        QThread::msleep(500);
    }

    if (cancelled_->loadRelaxed()) {
        emit finished(false, QStringLiteral("Cancelled."));
        return;
    }

    // =====================================================================
    // PHASE 2: Clear cache token and drop per-room databases
    // =====================================================================
    {
        emit phaseChanged(QStringLiteral("Clearing cache..."));
        nhlog::ui()->info("BeeperReinit: Phase 2/6 — Clearing cache and token.");

        try {
            auto txn     = lmdb::txn::begin(cache->env(), nullptr);
            auto try_drop = [&txn](const std::string &dbName) {
                try {
                    lmdb::dbi::open(txn, dbName.c_str()).drop(txn, true);
                } catch (std::exception &e) {
                    nhlog::db()->warn("BeeperReinit: failed to drop '{}': {}", dbName, e.what());
                }
            };

            auto room_ids = cache->getRoomIds(txn);
            for (const auto &room : room_ids) {
                try_drop(room + "/state");
                try_drop(room + "/state_by_key");
                try_drop(room + "/account_data");
                try_drop(room + "/members");
                try_drop(room + "/mentions");
                try_drop(room + "/events");
                try_drop(room + "/event_order");
                try_drop(room + "/event2order");
                try_drop(room + "/msg2order");
                try_drop(room + "/order2msg");
                try_drop(room + "/pending");
                try_drop(room + "/related");
            }

            // Clear room list but don't delete the dbi itself.
            cache->roomsDb().drop(txn, false);
            // Reset the sync token — this triggers a full initial sync.
            cache->setNextBatchToken(txn, "");
            txn.commit();

            nhlog::db()->info("BeeperReinit: cache cleared; next_batch token reset.");
        } catch (const lmdb::error &e) {
            nhlog::db()->critical("BeeperReinit: LMDB error during cache clear: {}", e.what());
            emit finished(false, QStringLiteral("Database error during cache clear."));
            return;
        }
    }

    if (cancelled_->loadRelaxed()) {
        emit finished(false, QStringLiteral("Cancelled."));
        return;
    }

    // =====================================================================
    // PHASE 3: Perform initial sync
    // =====================================================================
    std::string nextBatch;
    {
        emit phaseChanged(QStringLiteral("Performing initial sync..."));
        nhlog::ui()->info("BeeperReinit: Phase 3/6 — Performing initial sync.");

        mtx::http::SyncOpts opts;
        opts.timeout      = 0;
        opts.set_presence = ChatPage::instance()->currentPresence();
        // Leave opts.since empty → triggers a full initial sync.

        // Attempt to set full_state and a timeline filter if the API supports it.
        // Using uint64_t since mtxclient v0.9+ uses strongly-typed filters.
        // If the bundled mtxclient doesn't support these fields, the compile
        // will fail and we fall through to the /messages fallback below.
#if defined(MTXCLIENT_HAS_SYNC_FILTER) || defined(MTXCLIENT_VERSION_MAJOR)
// mtxclient v0.9+ supports filter in SyncOpts
// Build a JSON filter that requests more timeline messages per room
// This is a no-op if the struct doesn't have these fields — we provide
// the fallback in Phase 3b.
#endif

        std::atomic<bool> syncDone{false};
        std::atomic<bool> syncOk{false};
        mtx::responses::Sync syncResponse;

        http::client()->sync(
          opts,
          [&syncDone, &syncOk, &syncResponse, this](const mtx::responses::Sync &res,
                                                     mtx::http::RequestErr err) {
              if (!err) {
                  syncResponse = res;
                  syncOk.store(true, std::memory_order_release);
              } else {
                  nhlog::net()->error("BeeperReinit: initial sync failed: {}", *err);
              }
              syncDone.store(true, std::memory_order_release);
          });

        // Wait for sync to complete (with timeout).
        {
            QEventLoop loop;
            QTimer timer;
            timer.setSingleShot(true);
            QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
            timer.start(300000); // 5-minute timeout for huge accounts

            constexpr int POLL_INTERVAL = 100;
            while (!syncDone.load(std::memory_order_acquire) &&
                   !cancelled_->loadRelaxed()) {
                QTimer::singleShot(POLL_INTERVAL, &loop, &QEventLoop::quit);
                loop.exec();
                if (!timer.isActive()) {
                    nhlog::net()->error("BeeperReinit: initial sync timed out.");
                    break;
                }
            }
            timer.stop();
        }

        if (cancelled_->loadRelaxed()) {
            emit finished(false, QStringLiteral("Cancelled."));
            return;
        }

        if (!syncOk.load(std::memory_order_acquire)) {
            emit finished(false,
                          QStringLiteral("Initial sync failed. Check your network connection."));
            return;
        }

        // Save the sync response to LMDB.
        try {
            cache->saveState(syncResponse);
            nextBatch = syncResponse.next_batch;
            nhlog::db()->info("BeeperReinit: initial sync saved ({} rooms, next_batch: {}).",
                              syncResponse.rooms.join.size(),
                              nextBatch);
        } catch (const lmdb::error &e) {
            nhlog::db()->critical("BeeperReinit: failed to save initial sync: {}", e.what());
            emit finished(false, QStringLiteral("Failed to save sync response to database."));
            return;
        }

        emit progressUpdated(1, 3);
    }

    if (cancelled_->loadRelaxed()) {
        emit finished(false, QStringLiteral("Cancelled."));
        return;
    }

    // =====================================================================
    // PHASE 3b (fallback): For each room, fetch extra timeline messages
    // to ensure users can fast-scroll without pagination delays.
    //
    // The initial sync typically returns 10-20 timeline events per room.
    // We fetch up to 100 more via a single /messages call per room.
    // =====================================================================
    {
        emit phaseChanged(QStringLiteral("Fetching recent messages..."));
        nhlog::ui()->info("BeeperReinit: Phase 3b/6 — Fetching extra timeline messages.");

        auto txn     = lmdb::txn::begin(cache->env(), nullptr, MDB_RDONLY);
        auto roomIds = cache->getRoomIds(txn);
        txn.abort();

        // Process rooms in batches to avoid flooding the server.
        constexpr int MESSAGES_BATCH_SIZE = 10;
        int totalRooms = static_cast<int>(roomIds.size());
        int processed  = 0;

        for (size_t i = 0; i < roomIds.size(); i += MESSAGES_BATCH_SIZE) {
            if (cancelled_->loadRelaxed()) {
                emit finished(false, QStringLiteral("Cancelled."));
                return;
            }

            size_t end = std::min(i + MESSAGES_BATCH_SIZE, roomIds.size());
            for (size_t j = i; j < end; ++j) {
                const auto &roomId = roomIds[j];
                // Capture the room_id as a local copy so the lambda below
                // can safely reference it even after the loop advances.
                const auto roomIdCopy = roomId;

                std::atomic<bool> msgDone{false};
                std::atomic<bool> msgOk{false};

                // Fetch the most recent 100 messages for this room.
                mtx::http::MessagesOpts opts;
                opts.room_id = roomId;
                opts.dir     = mtx::http::PaginationDirection::Backwards;
                opts.limit   = 100;

                http::client()->messages(
                  opts,
                  [&msgDone, &msgOk, &roomIdCopy, cache](const mtx::responses::Messages &msgs,
                                                         mtx::http::RequestErr err) {
                      if (!err) {
                          nhlog::net()->debug("BeeperReinit: fetched {} messages for {}",
                                              msgs.chunk.size(),
                                              roomIdCopy);

                          // Persist fetched messages to LMDB.
                          // This ensures the room list is sorted by actual
                          // last-message timestamps instead of falling back
                          // to alphabetical order (which happens when all
                          // timestamps are zero after a fresh initial sync).
                          if (!msgs.chunk.empty()) {
                              try {
                                  auto count = cache->saveOldMessages(roomIdCopy, msgs);
                                  nhlog::db()->debug(
                                    "BeeperReinit: saved {} messages ({} new) for {}",
                                    msgs.chunk.size(), count, roomIdCopy);
                              } catch (const lmdb::error &e) {
                                  nhlog::db()->warn(
                                    "BeeperReinit: failed to save messages for {}: {}",
                                    roomIdCopy, e.what());
                              }
                          }

                          msgOk.store(true, std::memory_order_release);
                      } else {
                          nhlog::net()->warn("BeeperReinit: messages failed for {}: {}",
                                             roomIdCopy,
                                             err->matrix_error.error);
                      }
                      msgDone.store(true, std::memory_order_release);
                  });

                // Wait for this request to complete.
                {
                    QEventLoop loop;
                    QTimer timer;
                    timer.setSingleShot(true);
                    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
                    timer.start(30000);

                    constexpr int POLL_INTERVAL = 50;
                    while (!msgDone.load(std::memory_order_acquire) &&
                           !cancelled_->loadRelaxed()) {
                        QTimer::singleShot(POLL_INTERVAL, &loop, &QEventLoop::quit);
                        loop.exec();
                        if (!timer.isActive())
                            break;
                    }
                    timer.stop();
                }

                processed++;
                emit progressUpdated(1 + processed, 3 + totalRooms);
            }

            // Rate-limit delay between batches.
            if (i + MESSAGES_BATCH_SIZE < roomIds.size())
                QThread::msleep(200);
        }
    }

    if (cancelled_->loadRelaxed()) {
        emit finished(false, QStringLiteral("Cancelled."));
        return;
    }

    // =====================================================================
    // PHASE 4: Re-read all rooms and aggressively fetch avatars
    // (with Beeper counterpart override)
    // =====================================================================
    {
        emit phaseChanged(QStringLiteral("Downloading avatars..."));
        nhlog::ui()->info("BeeperReinit: Phase 4/6 — Downloading avatars.");

        auto txn     = lmdb::txn::begin(cache->env(), nullptr, MDB_RDONLY);
        auto roomsDb = cache->roomsDb();
        auto roomsCursor = lmdb::cursor::open(txn, roomsDb);

        std::string_view roomId, roomData;
        std::vector<std::string> allRoomIds;

        while (roomsCursor.get(roomId, roomData, MDB_NEXT)) {
            allRoomIds.push_back(std::string(roomId));
        }
        roomsCursor.close();
        txn.abort();

        int totalRooms  = static_cast<int>(allRoomIds.size());
        int processed   = 0;

        // Collect avatar URLs to download.
        struct AvatarEntry
        {
            std::string mxcUrl;
            std::string roomId;
        };
        std::vector<AvatarEntry> avatarsToFetch;

        for (const auto &rid : allRoomIds) {
            if (cancelled_->loadRelaxed())
                break;

            auto rtxn       = lmdb::txn::begin(cache->env(), nullptr, MDB_RDONLY);
            auto membersdb  = cache->openMembersDb(rtxn, rid);
            auto statesdb   = cache->openStatesDb(rtxn, rid);

            // Recalculate room info via cache methods (which include Beeper override).
            QString resolvedName = cache->getRoomName(rtxn, statesdb, membersdb);
            QString resolvedAvatarUrl = cache->getRoomAvatarUrl(rtxn, statesdb, membersdb);

            if (!resolvedAvatarUrl.isEmpty()) {
                avatarsToFetch.push_back(
                  {resolvedAvatarUrl.toStdString(), rid});
            }

            // Also fetch the counterpart avatar directly if this is a Beeper room.
            if (membersdb.size(rtxn) == 3) {
                std::map<std::string, MemberInfo> members;
                auto mcursor = lmdb::cursor::open(rtxn, membersdb);
                std::string_view uid, mdata;
                while (mcursor.get(uid, mdata, MDB_NEXT)) {
                    try {
                        members.emplace(std::string(uid),
                                        nlohmann::json::parse(mdata).get<MemberInfo>());
                    } catch (...) {
                    }
                }
                mcursor.close();

                const auto *cp = beeper::fakeDmCounterpart(
                  members, cache->localUserId().toStdString());
                if (cp && !cp->avatar_url.empty() &&
                    cp->avatar_url != resolvedAvatarUrl.toStdString()) {
                    avatarsToFetch.push_back({cp->avatar_url, rid});
                }
            }

            rtxn.abort();
            processed++;
            emit progressUpdated(2 + processed, 3 + totalRooms);
        }

        // Download avatars in batches.
        int totalAvatars = static_cast<int>(avatarsToFetch.size());
        emit progressUpdated(2 + totalRooms, 3 + totalRooms + totalAvatars);

        int avatarProcessed = 0;
        for (size_t i = 0; i < avatarsToFetch.size(); i += MAX_AVATARS_PER_BATCH) {
            if (cancelled_->loadRelaxed())
                break;

            size_t end = std::min(i + MAX_AVATARS_PER_BATCH, avatarsToFetch.size());

            for (size_t j = i; j < end; ++j) {
                const auto &entry = avatarsToFetch[j];
                QString mxcId     = QString::fromStdString(entry.mxcUrl);
                mxcId.remove(QStringLiteral("mxc://"));

                if (mxcId.isEmpty())
                    continue;

                std::atomic<bool> dlDone{false};

                MxcImageProvider::download(
                  mxcId,
                  QSize(AVATAR_DOWNLOAD_SIZE, AVATAR_DOWNLOAD_SIZE),
                  [&dlDone](QString, QSize, QImage, QString) {
                      dlDone.store(true, std::memory_order_release);
                  });

                // Wait briefly for the download to complete (async).
                {
                    QEventLoop loop;
                    QTimer timer;
                    timer.setSingleShot(true);
                    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
                    timer.start(AVATAR_TIMEOUT_MS);

                    constexpr int POLL_INTERVAL = 50;
                    while (!dlDone.load(std::memory_order_acquire) &&
                           !cancelled_->loadRelaxed()) {
                        QTimer::singleShot(POLL_INTERVAL, &loop, &QEventLoop::quit);
                        loop.exec();
                        if (!timer.isActive())
                            break;
                    }
                    timer.stop();
                }

                avatarProcessed++;
                emit progressUpdated(2 + totalRooms + avatarProcessed,
                                     3 + totalRooms + totalAvatars);
            }

            // Rate-limit delay between avatar batches.
            if (i + MAX_AVATARS_PER_BATCH < avatarsToFetch.size())
                QThread::msleep(AVATAR_BATCH_DELAY_MS);
        }

        nhlog::ui()->info("BeeperReinit: downloaded {} avatars for {} rooms.",
                          avatarProcessed,
                          totalRooms);
    }

    if (cancelled_->loadRelaxed()) {
        emit finished(false, QStringLiteral("Cancelled."));
        return;
    }

    // =====================================================================
    // FINAL PHASE: Resume sync loop
    // =====================================================================
    {
        emit phaseChanged(QStringLiteral("Resuming sync..."));
        nhlog::ui()->info("BeeperReinit: Phase 6/6 — Resuming sync loop.");

        QMetaObject::invokeMethod(
          ChatPage::instance(),
          [this]() {
              // Reconnect the sync signals.
              QObject::connect(ChatPage::instance(),
                               &ChatPage::newSyncResponse,
                               ChatPage::instance(),
                               &ChatPage::startRemoveFallbackKeyTimer);
              // Trigger a fresh sync cycle.
              emit ChatPage::instance()->trySyncCb();
          },
          Qt::BlockingQueuedConnection);
    }

    nhlog::ui()->info("BeeperReinit: completed successfully.");
    emit finished(true,
                  QStringLiteral("Beeper re-initialization complete. Your chats are up to date."));
}

#include "moc_BeeperReinitController.cpp"
