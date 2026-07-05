// SPDX-FileCopyrightText: Nheko Contributors
//
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import im.nheko

/// Modal overlay shown during the Beeper full re-initialization.
/// Blocks all underlying mouse interaction while the operation runs.
/// Displays the current phase and progress to the user.
Rectangle {
    id: root

    /// Current phase label (set by BeeperReinitController.reinitPhaseChanged).
    property string currentPhase: ""
    /// Progress values emitted by the controller.
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
        propagateComposedEvents: false
    }

    visible: inProgress

    ColumnLayout {
        anchors.centerIn: parent
        spacing: Nheko.paddingLarge
        width: Math.min(450, parent.width * 0.85)

        BusyIndicator {
            id: spinner
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            running: root.inProgress
        }

        Label {
            id: phaseLabel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            font.pointSize: fontMetrics.font.pointSize * 1.1
            font.bold: true
            text: root.currentPhase
        }

        ProgressBar {
            id: progressBar
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            from: 0
            to: Math.max(1, root.progressTotal)
            value: root.progressCurrent
            indeterminate: root.progressTotal === 0

            contentItem: Item {
                implicitHeight: 6
                Rectangle {
                    id: bar
                    width: progressBar.visualPosition * parent.width
                    height: parent.height
                    radius: 3
                    color: Nheko.theme.highlight
                }
            }
        }

        Label {
            id: progressLabel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pointSize: fontMetrics.font.pointSize * 0.85
            text: {
                if (root.progressTotal > 0)
                    return qsTr("%1 / %2").arg(root.progressCurrent).arg(root.progressTotal);
                else
                    return "";
            }
        }

        Label {
            id: warningLabel
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            color: Qt.rgba(1, 0.7, 0.7, 0.8)
            font.pointSize: fontMetrics.font.pointSize * 0.8
            text: qsTr("This may take several minutes. Please do not close Nheko.")
            visible: root.inProgress
            wrapMode: Text.WordWrap
        }
    }

    // Connect to the controller signals.
    Connections {
        target: BeeperReinitController

        function onReinitStarted() {
            root.progressCurrent = 0;
            root.progressTotal = 0;
            root.currentPhase = qsTr("Starting...");
            root.inProgress = true;
        }

        function onReinitPhaseChanged(phase) {
            root.currentPhase = phase;
        }

        function onReinitProgressUpdated(current, total) {
            root.progressCurrent = current;
            root.progressTotal = total;
        }

        function onReinitFinished(success, message) {
            root.inProgress = false;
            root.currentPhase = "";
            if (success) {
                console.log("Beeper re-init succeeded:", message);
            } else {
                console.warn("Beeper re-init failed:", message);
            }
        }
    }
}
