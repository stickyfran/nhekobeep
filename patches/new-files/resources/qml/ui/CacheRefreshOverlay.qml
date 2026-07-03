// SPDX-FileCopyrightText: Nheko Contributors
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import im.nheko

/// Modal overlay shown during cache refresh.
/// Blocks all underlying mouse interaction while the refresh runs.
Rectangle {
    id: root

    /// Bind to CacheRefreshController.progressUpdated(current, total)
    property int progressCurrent: 0
    property int progressTotal: 0
    property bool inProgress: false

    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.6)
    z: 9999

    // Block all clicks beneath the overlay.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: false
        // Consume all mouse events so they don't pass through.
        propagateComposedEvents: false
        // No onClicked needed - we just block.
    }

    visible: inProgress

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Nheko.paddingLarge
        width: Math.min(400, parent.width * 0.8)

        BusyIndicator {
            id: spinner
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            running: root.inProgress
        }

        ProgressBar {
            id: progressBar
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            from: 0
            to: Math.max(1, root.progressTotal)
            value: root.progressCurrent
            indeterminate: root.progressTotal === 0
        }

        Label {
            id: statusLabel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            font.pointSize: fontMetrics.font.pointSize * 1.1
            text: {
                if (!root.inProgress)
                    return "";
                if (root.progressTotal > 0)
                    return qsTr("Updating cache and downloading avatars...\n%1 / %2 rooms").arg(root.progressCurrent).arg(root.progressTotal);
                else
                    return qsTr("Preparing cache refresh...");
            }
        }

        Label {
            id: detailLabel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pointSize: fontMetrics.font.pointSize * 0.85
            visible: root.inProgress && root.progressTotal > 0
            text: qsTr("Please wait while your chat data is updated.")
        }
    }

    // Connect to the controller signals.
    Connections {
        target: CacheRefreshController

        function onRefreshStarted() {
            root.progressCurrent = 0;
            root.progressTotal = 0;
            root.inProgress = true;
        }

        function onProgressUpdated(current, total) {
            root.progressCurrent = current;
            root.progressTotal = total;
        }

        function onRefreshFinished(success, message) {
            root.inProgress = false;
            // Show a brief toast/snackbar with the result.
            if (success) {
                console.log("Cache refresh succeeded:", message);
            } else {
                console.warn("Cache refresh failed:", message);
            }
        }
    }
}
