// SPDX-FileCopyrightText: Nheko Contributors
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QThread>
#include <QAtomicInt>

class BeeperReinitWorker;

//! BeeperReinitController triggers a full destructive re-initialization of the
//! account's state, history, and avatars ("Beeper Full Re-Init").
//!
//! Sequence:
//!   1. Pause the sync loop
//!   2. Clear all per-room LMDB databases + reset next_batch_token
//!   3. Perform a deep initial /sync (or fallback: per-room /messages)
//!   4. Aggressively fetch all member avatars
//!   5. Resume the sync loop
//!
//! The heavy work runs on a dedicated QThread so the UI stays responsive.
class BeeperReinitController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit BeeperReinitController(QObject *parent = nullptr);
    ~BeeperReinitController() override;

    //! Start the full re-initialization cycle.
    Q_INVOKABLE void startBeeperReinit();

signals:
    void reinitStarted();
    //! Reports a human-readable phase label (e.g. "Pausing sync...",
    //! "Clearing cache...", "Performing initial sync...",
    //! "Downloading avatars...", "Resuming sync...").
    void reinitPhaseChanged(QString phase);
    void reinitProgressUpdated(int current, int total);
    void reinitFinished(bool success, QString message);

private:
    QThread workerThread_;
    QAtomicInt cancelled_{0};
};

//! Worker object that lives on the background QThread.
class BeeperReinitWorker : public QObject
{
    Q_OBJECT

public:
    explicit BeeperReinitWorker(QAtomicInt *cancelFlag, QObject *parent = nullptr);

public slots:
    void process();

signals:
    void phaseChanged(QString phase);
    void progressUpdated(int current, int total);
    void finished(bool success, QString message);

private:
    QAtomicInt *cancelled_;
};
