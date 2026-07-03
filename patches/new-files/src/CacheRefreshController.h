// SPDX-FileCopyrightText: Nheko Contributors
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QThread>
#include <QAtomicInt>

class CacheRefreshWorker;

//! CacheRefreshController exposes a cache-force-refresh operation to QML.
//!
//! It runs the refresh on a dedicated QThread so the UI stays responsive.
//! The class registers itself as a QML singleton so QML code can invoke
//! startCacheRefresh() directly and subscribe to its signals.
class CacheRefreshController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit CacheRefreshController(QObject *parent = nullptr);
    ~CacheRefreshController() override;

    //! Start the refresh cycle.
    //! Emits refreshStarted() immediately, then runs the heavy work on a
    //! background thread and finally emits refreshFinished() when done.
    Q_INVOKABLE void startCacheRefresh();

signals:
    void refreshStarted();
    void progressUpdated(int current, int total);
    void refreshFinished(bool success, QString message);

private:
    QThread workerThread_;
    QAtomicInt cancelled_{0};
};

//! Worker object that lives on the background QThread.
//! Receives a signal to begin and emits progress / completion signals.
class CacheRefreshWorker : public QObject
{
    Q_OBJECT

public:
    explicit CacheRefreshWorker(QAtomicInt *cancelFlag, QObject *parent = nullptr);

public slots:
    void process();

signals:
    void progressUpdated(int current, int total);
    void finished(bool success, QString message);

private:
    QAtomicInt *cancelled_;
};
