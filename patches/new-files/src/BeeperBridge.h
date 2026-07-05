// SPDX-FileCopyrightText: Nheko Contributors
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <map>
#include <string>
#include <string_view>

#include "CacheStructs.h"

//
// Beeper "fake DM" detection helpers.
//
// Beeper bridges (Instagram, WhatsApp, etc.) model 1:1 chats as 3-member
// rooms: <local user, real contact, @<service>bot:beeper.<tld>>. These
// helpers identify the bridge bot and the real counterpart so we can
// render the room as a native Matrix DM instead of a tiny group.
//
namespace beeper {

//! Check whether the given Matrix ID is a Beeper bridge bot.
//! Bridge bots have MXIDs matching @*bot*:beeper.*
inline bool
isBridgeBotMxid(std::string_view mxid)
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

//! Given a fully-populated <mxid -> MemberInfo> map of a candidate Beeper
//! room (exactly 3 members), returns a pointer to the real counterpart's
//! MemberInfo, or nullptr when the room is NOT a Beeper bridge room.
inline const MemberInfo *
fakeDmCounterpart(const std::map<std::string, MemberInfo> &members,
                  const std::string &localUserId)
{
    if (members.size() != 3)
        return nullptr;

    bool hasLocal             = false;
    bool hasBot               = false;
    const MemberInfo *contact = nullptr;

    for (const auto &[mxid, info] : members) {
        if (mxid == localUserId) {
            hasLocal = true;
        } else if (isBridgeBotMxid(mxid)) {
            hasBot = true;
        } else {
            // Only accept a single non-local, non-bot member as the
            // counterpart; otherwise this isn't a 1:1-shaped room.
            if (contact)
                return nullptr;
            contact = &info;
        }
    }

    return (hasLocal && hasBot) ? contact : nullptr;
}

//! Variant that returns the counterpart's MXID string (empty on failure).
inline std::string
fakeDmCounterpartMxid(const std::map<std::string, MemberInfo> &members,
                      const std::string &localUserId)
{
    const auto *cp = fakeDmCounterpart(members, localUserId);
    if (!cp)
        return {};

    // Find the MXID associated with the returned MemberInfo pointer.
    for (const auto &[mxid, info] : members) {
        if (&info == cp)
            return mxid;
    }
    return {};
}

} // namespace beeper
