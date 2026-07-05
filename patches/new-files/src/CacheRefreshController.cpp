// SPDX-FileCopyrightText: Nheko Contributors
//
// SPDX-License-Identifier: GPL-3.0-or-later

#include "CacheRefreshController.h"

#include <atomic>
#include <QEventLoop>
#include <QTimer>
#include <QThread>
#include <QElapsedTimer>
#include <QMap>
#include <QMutexLocker>

#include <nlohmann/json.hpp>

#include <mtx/responses/profile.hpp>
#include <mtxclient/http/client.hpp>
#include <mtx/events.hpp>
#include <mtx/events/collections.hpp>

#include "Cache_p.h"
#include "CacheStructs.h"
#include "Logging.h"
#include "MatrixClient.h"
#include "MxcImageProvider.h"
#include "Utils.h"

// ---------------------------------------------------------------------------
// Beeper bridge detection helpers (mirror the logic from Cache.cpp)
// ---------------------------------------------------------------------------
namespace {

bool
isBeeperBridgeBotMxid(std::string_view mxid)
{
    if (mxid.size() < 4 || mxid.front() != '@')
        return false;

    const auto colon = mxid.find(':');
    if (colon == std::string_view::npos || colon + 1 >= mxid.size())
        return false;

    const auto localpart = mxid.substr(1, colon - 1);
    const auto server    = mxid.substr(colon + 1);

    // server must start with "beeper." (e.g. beeper.local, beeper.com)
    if (server.size() < 7 || server.compare(0, 7, "beeper.") != 0)
        return false;

    // localpart must contain "bot" (case-insensitive)
    auto toLower = [](char c) -> char {
        return (c >= 'A' && c <= 'Z') ? static_cast<char>(c + ('a' - 'A')) : c;
    };
    for (size_t i = 0; i + 3 <= localpart.size(); ++i) {
        if (toLower(localpart[i]) == 'b' && toLower(localpart[i + 1]) == 'o' &&
            toLower(localpart[i + 2]) == 't')
            return true;
    }
    return false;
}

// Given a fully-populated <mxid -> MemberInfo> map of a candidate Beeper
// room (exactly 3 members), returns the real counterpart's mxid or empty.
// Returns empty when the room is NOT a Beeper bridge room.
std::string
beeperFakeDmCounterpartMxid(const std::map<std::string, MemberInfo> &members,
                            const std::string &localUserId)
{
    if (members.size() != 3)
        return {};

    bool hasLocal = false;
    bool hasBot   = false;
    std::string contactMxid;

    for (const auto &[mxid, info] : members) {
        if (mxid == localUserId) {
            hasLocal = true;
        } else if (isBeeperBridgeBotMxid(mxid)) {
            hasBot = true;
        } else {
            if (!contactMxid.empty())
                return {}; // more than one contact – not a DM
            contactMxid = mxid;
        }
    }

    return (hasLocal && hasBot && !contactMxid.empty()) ? contactMxid : std::string{};
}

} // namespace

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
static constexpr int BATCH_SIZE               = 50;
static constexpr int RATE_LIMIT_DELAY_MS      = 200;
static constexpr int PROFILE_TIMEOUT_MS       = 30000; // 30s per profile
static constexpr int AVATAR_DOWNLOAD_SIZE     = 128;

// ---------------------------------------------------------------------------
// CacheRefreshController
// ---------------------------------------------------------------------------
CacheRefreshController::CacheRefreshController(QObject *parent)
  : QObject(parent)
{
    workerThread_.setObjectName(QStringLiteral("cache-refresh-worker"));
}

CacheRefreshController::~CacheRefreshController()
{
    cancelled_.storeRelaxed(1);
    workerThread_.quit();
    workerThread_.wait();
}

void
CacheRefreshController::startCacheRefresh()
{
    if (workerThread_.isRunning()) {
        nhlog::ui()->warn("Cache refresh already in progress, ignoring duplicate request.");
        return;
    }

    cancelled_.storeRelaxed(0);

    auto *worker = new CacheRefreshWorker(&cancelled_);
    worker->moveToThread(&workerThread_);

    // Forward progress signals from the worker to the QML-facing signals.
    connect(worker,
            &CacheRefreshWorker::progressUpdated,
            this,
            &CacheRefreshController::progressUpdated);
    connect(worker, &CacheRefreshWorker::finished, this, [this](bool ok, QString msg) {
        emit refreshFinished(ok, msg);
    });

    // Clean up worker when done.
    connect(worker, &CacheRefreshWorker::finished, worker, &QObject::deleteLater);
    connect(&workerThread_, &QThread::finished, worker, &QObject::deleteLater);

    // Kick off the work when the thread starts.
    connect(&workerThread_, &QThread::started, worker, &CacheRefreshWorker::process);

    emit refreshStarted();
    workerThread_.start();
}

// ---------------------------------------------------------------------------
// Helper: synchronous profile fetch using a nested event loop.
//
// The mtxclient HTTP callback fires on an internal I/O thread.  We use
// std::atomic<bool> guards and a local QEventLoop to bridge the threads.
// Returns true on success and fills out name/avatarUrl.
// ---------------------------------------------------------------------------
static bool
fetchProfileSync(const std::string &mxid,
                 std::string &outName,
                 std::string &outAvatarUrl,
                 int timeoutMs,
                 const QAtomicInt *cancelFlag)
{
    std::atomic<bool> done{false};
    std::atomic<bool> success{false};
    std::string name, avatar;

    http::client()->get_profile(
      mxid,
      [&done, &success, &name, &avatar, &mxid](const mtx::responses::Profile &res,
                                                mtx::http::RequestErr err) {
          if (!err) {
              name    = res.display_name;
              avatar  = res.avatar_url;
              success.store(true, std::memory_order_release);
          } else {
              nhlog::net()->warn("CacheRefresh: get_profile failed for {}: {}",
                                 mxid,
                                 err->matrix_error.error);
          }
          done.store(true, std::memory_order_release);
      });

    // Spin a local event loop until the async callback fires or timeout.
    QEventLoop loop;
    QTimer timer;
    timer.setSingleShot(true);
    QObject::connect(&timer, &QTimer::timeout, &loop, &QEventLoop::quit);
    timer.start(timeoutMs);

    constexpr int POLL_INTERVAL = 50; // ms
    while (!done.load(std::memory_order_acquire) && !cancelFlag->loadRelaxed()) {
        QTimer::singleShot(POLL_INTERVAL, &loop, &QEventLoop::quit);
        loop.exec();
        if (!timer.isActive()) {
            nhlog::net()->warn("CacheRefresh: profile fetch timed out for {}", mxid);
            break;
        }
    }

    timer.stop();

    if (success.load(std::memory_order_acquire)) {
        outName       = std::move(name);
        outAvatarUrl  = std::move(avatar);
    }
    return success.load(std::memory_order_acquire);
}

// ---------------------------------------------------------------------------
// CacheRefreshWorker
// ---------------------------------------------------------------------------
CacheRefreshWorker::CacheRefreshWorker(QAtomicInt *cancelFlag, QObject *parent)
  : QObject(parent)
  , cancelled_(cancelFlag)
{
}

void
CacheRefreshWorker::process()
{
    nhlog::ui()->info("Cache refresh worker started.");

    // -----------------------------------------------------------------------
    // 1. Obtain all joined rooms sorted by last activity (descending).
    // -----------------------------------------------------------------------
    auto *cache = cache::client();
    if (!cache || !cache->isDatabaseReady()) {
        emit finished(false, QStringLiteral("Database not ready."));
        return;
    }

    // Fetch all room IDs from the rooms database.
    std::vector<std::string> allRoomIds;
    {
        auto txn         = lmdb::txn::begin(cache->env(), nullptr, MDB_RDONLY);
        auto roomsDb     = cache->roomsDb();
        auto roomsCursor = lmdb::cursor::open(txn, roomsDb);
        std::string_view roomId, roomData;

        while (roomsCursor.get(roomId, roomData, MDB_NEXT)) {
            allRoomIds.push_back(std::string(roomId));
        }
        roomsCursor.close();
        txn.abort();
    }

    if (allRoomIds.empty()) {
        emit finished(true, QStringLiteral("No rooms found. Nothing to refresh."));
        return;
    }

    // Read RoomInfo for each room to sort by last modification timestamp,
    // and detect Beeper bridge rooms.
    struct RoomEntry
    {
        std::string room_id;
        uint64_t last_activity     = 0;
        bool is_beeper_room        = false;
        std::string beeper_contact_id;
    };
    QVector<RoomEntry> entries;
    entries.reserve(static_cast<int>(allRoomIds.size()));

    {
        auto txn     = lmdb::txn::begin(cache->env(), nullptr, MDB_RDONLY);
        auto roomsDb = cache->roomsDb();

        for (const auto &rid : allRoomIds) {
            if (cancelled_->loadRelaxed())
                break;

            RoomEntry entry;
            entry.room_id = rid;

            std::string_view roomData;
            if (roomsDb.get(txn, rid, roomData)) {
                try {
                    auto info     = nlohmann::json::parse(roomData).get<RoomInfo>();
                    entry.last_activity = info.approximate_last_modification_ts;

                    // Detect Beeper bridge rooms: 3 members, one is a bot.
                    auto membersdb = cache->openMembersDb(txn, rid);
                    if (membersdb.size(txn) == 3) {
                        std::map<std::string, MemberInfo> members;
                        auto mcursor = lmdb::cursor::open(txn, membersdb);
                        std::string_view uid, mdata;
                        while (mcursor.get(uid, mdata, MDB_NEXT)) {
                            try {
                                members.emplace(
                                  std::string(uid),
                                  nlohmann::json::parse(mdata).get<MemberInfo>());
                            } catch (...) {
                            }
                        }
                        mcursor.close();

                        auto contact =
                          beeperFakeDmCounterpartMxid(members,
                                                      cache->localUserId().toStdString());
                        if (!contact.empty()) {
                            entry.is_beeper_room    = true;
                            entry.beeper_contact_id = std::move(contact);
                        }
                    }
                } catch (const nlohmann::json::exception &e) {
                    nhlog::db()->warn("CacheRefresh: failed to parse RoomInfo for {}: {}",
                                      rid,
                                      e.what());
                }
            }
            entries.push_back(std::move(entry));
        }
        txn.abort();
    }

    // Sort: Beeper rooms first (prioritize), then by last activity descending.
    std::sort(entries.begin(), entries.end(), [](const RoomEntry &a, const RoomEntry &b) {
        if (a.is_beeper_room != b.is_beeper_room)
            return a.is_beeper_room > b.is_beeper_room;
        return a.last_activity > b.last_activity;
    });

    // Process ALL rooms (no artificial limit).
    int totalToProcess = static_cast<int>(entries.size());
    if (totalToProcess == 0) {
        emit finished(true, QStringLiteral("All rooms processed."));
        return;
    }

    int beeperCount = 0;
    for (int i = 0; i < totalToProcess; ++i) {
        if (entries[i].is_beeper_room)
            beeperCount++;
    }
    nhlog::ui()->info("CacheRefresh: processing {} rooms ({} Beeper priority).",
                      totalToProcess,
                      beeperCount);

    emit progressUpdated(0, totalToProcess);

    // -----------------------------------------------------------------------
    // 2. Process rooms in batches.
    // -----------------------------------------------------------------------
    int processed       = 0;
    int beeperProcessed = 0;

    // Accumulate member profile updates per room; flushed every BATCH_SIZE.
    struct MemberUpdate
    {
        std::string user_id;
        std::string display_name;
        std::string avatar_url;
    };
    QMap<std::string, QVector<MemberUpdate>> pendingUpdates;

    for (int i = 0; i < totalToProcess; ++i) {
        if (cancelled_->loadRelaxed()) {
            nhlog::ui()->info("Cache refresh cancelled by user.");
            emit finished(false, QStringLiteral("Cancelled."));
            return;
        }

        const auto &entry  = entries[i];
        const auto &roomId = entry.room_id;

        // Collect member mxids to refresh for this room.
        std::vector<std::string> memberIds;
        bool isDmOrBeeper = false;

        if (entry.is_beeper_room && !entry.beeper_contact_id.empty()) {
            // Beeper room: only refresh the real contact.
            memberIds.push_back(entry.beeper_contact_id);
            isDmOrBeeper = true;
        } else {
            auto txn      = lmdb::txn::begin(cache->env(), nullptr, MDB_RDONLY);
            auto membersdb = cache->openMembersDb(txn, roomId);
            auto cursor   = lmdb::cursor::open(txn, membersdb);
            std::string_view uid, mdata;
            while (cursor.get(uid, mdata, MDB_NEXT)) {
                std::string mxid(uid);
                if (mxid != cache->localUserId().toStdString()) {
                    memberIds.push_back(std::move(mxid));
                }
            }
            cursor.close();
            txn.abort();

            isDmOrBeeper = (memberIds.size() == 1);
        }

        if (memberIds.empty()) {
            processed++;
            emit progressUpdated(processed, totalToProcess);
            continue;
        }

        // Fetch profiles for each member.
        for (const auto &mxid : memberIds) {
            if (cancelled_->loadRelaxed())
                break;

            std::string fetchedName;
            std::string fetchedAvatarUrl;
            bool fetchedOk = false;

            // Retry up to 3 times with exponential backoff.
            for (int attempt = 0; attempt < 3; ++attempt) {
                if (cancelled_->loadRelaxed())
                    break;

                fetchedOk = fetchProfileSync(mxid,
                                             fetchedName,
                                             fetchedAvatarUrl,
                                             PROFILE_TIMEOUT_MS,
                                             cancelled_);
                if (fetchedOk)
                    break;

                // Exponential backoff: 200ms, 400ms, 800ms.
                int delay = RATE_LIMIT_DELAY_MS * (1 << attempt);
                nhlog::net()->info("CacheRefresh: retrying {} in {}ms (attempt {})",
                                   mxid,
                                   delay,
                                   attempt + 1);
                QThread::msleep(static_cast<unsigned long>(delay));
            }

            if (!fetchedOk)
                continue;

            // Enqueue the LMDB update.
            auto &updates = pendingUpdates[roomId];
            auto it       = std::find_if(updates.begin(),
                                  updates.end(),
                                  [&mxid](const MemberUpdate &mu) { return mu.user_id == mxid; });
            if (it != updates.end()) {
                it->display_name = fetchedName;
                it->avatar_url   = fetchedAvatarUrl;
            } else {
                updates.push_back({mxid, fetchedName, fetchedAvatarUrl});
            }

            // Download avatar into the media cache.
            if (!fetchedAvatarUrl.empty()) {
                QString mxcId = QString::fromStdString(fetchedAvatarUrl);
                mxcId.remove(QStringLiteral("mxc://"));
                if (!mxcId.isEmpty()) {
                    MxcImageProvider::download(
                      mxcId,
                      QSize(AVATAR_DOWNLOAD_SIZE, AVATAR_DOWNLOAD_SIZE),
                      [mxid](QString, QSize, QImage, QString) {
                          // Avatar now cached locally.
                      });
                }
            }

            if (isDmOrBeeper)
                break;
        }

        processed++;
        emit progressUpdated(processed, totalToProcess);

        if (entry.is_beeper_room)
            beeperProcessed++;

        // -------------------------------------------------------------------
        // 3. Flush LMDB writes every BATCH_SIZE rooms.
        // -------------------------------------------------------------------
        if (processed % BATCH_SIZE == 0 || i == totalToProcess - 1) {
            if (!pendingUpdates.isEmpty()) {
                try {
                    auto txn     = lmdb::txn::begin(cache->env());
                    auto roomsDb = cache->roomsDb();

                    for (auto it = pendingUpdates.begin(); it != pendingUpdates.end(); ++it) {
                        const auto &rid     = it.key();
                        const auto &updates = it.value();

                        auto membersdb = cache->openMembersDb(txn, rid);
                        auto statesdb  = cache->openStatesDb(txn, rid);

                        for (const auto &update : updates) {
                            std::string_view existingData;
                            MemberInfo memberInfo;
                            if (membersdb.get(txn, update.user_id, existingData)) {
                                try {
                                    memberInfo =
                                      nlohmann::json::parse(existingData)
                                        .get<MemberInfo>();
                                } catch (...) {
                                }
                            } else {
                                memberInfo.name = update.user_id;
                            }

                            if (!update.display_name.empty())
                                memberInfo.name = update.display_name;
                            if (!update.avatar_url.empty())
                                memberInfo.avatar_url = update.avatar_url;

                            membersdb.put(txn,
                                          update.user_id,
                                          nlohmann::json(memberInfo).dump());
                        }

                        // Recalculate room-level name and avatar from updated members.
                        RoomInfo updatedInfo;
                        updatedInfo.name =
                          cache->getRoomName(txn, statesdb, membersdb).toStdString();
                        updatedInfo.avatar_url =
                          cache->getRoomAvatarUrl(txn, statesdb, membersdb).toStdString();
                        updatedInfo.topic        = cache->getRoomTopic(txn, statesdb).toStdString();
                        updatedInfo.version      = cache->getRoomVersion(txn, statesdb).toStdString();
                        updatedInfo.is_space     = cache->getRoomIsSpace(txn, statesdb);
                        updatedInfo.is_tombstoned = cache->getRoomIsTombstoned(txn, statesdb);

                        // Preserve fields we don't recalculate.
                        std::string_view existingRoomData;
                        if (roomsDb.get(txn, rid, existingRoomData)) {
                            try {
                                auto existing =
                                  nlohmann::json::parse(existingRoomData).get<RoomInfo>();
                                updatedInfo.member_count   = existing.member_count;
                                updatedInfo.join_rule      = existing.join_rule;
                                updatedInfo.guest_access   = existing.guest_access;
                                updatedInfo.tags           = existing.tags;
                                updatedInfo.approximate_last_modification_ts =
                                  existing.approximate_last_modification_ts;
                                updatedInfo.highlight_count    = existing.highlight_count;
                                updatedInfo.notification_count = existing.notification_count;
                            } catch (...) {
                            }
                        }

                        roomsDb.put(txn, rid, nlohmann::json(updatedInfo).dump());
                    }

                    txn.commit();
                    pendingUpdates.clear();

                    nhlog::db()->info("CacheRefresh: flushed batch of updates.");
                } catch (const lmdb::error &e) {
                    nhlog::db()->critical("CacheRefresh: LMDB write error: {}", e.what());
                    emit finished(false,
                                  QStringLiteral("Database write error: %1").arg(e.what()));
                    return;
                }
            }

            // Rate-limit delay between batches.
            if (i < totalToProcess - 1)
                QThread::msleep(RATE_LIMIT_DELAY_MS);
        }
    }

    nhlog::ui()->info("Cache refresh finished. Processed {} rooms ({} Beeper).",
                      processed,
                      beeperProcessed);

    emit finished(true,
                  QStringLiteral("Cache refresh complete. Processed %1 rooms (%2 Beeper chats).")
                    .arg(processed)
                    .arg(beeperProcessed));
}

#include "moc_CacheRefreshController.cpp"
