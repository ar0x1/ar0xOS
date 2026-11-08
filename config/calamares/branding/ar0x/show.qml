// /etc/calamares/branding/ar0x/show.qml — Phase 10
// Calamares slideshow API v2 (loaded at startup). Pure QML, no QML modules
// beyond QtQuick, so it works with the Qt6 runtime Calamares 3.4.3 ships.
// ADR-015 palette pins are repeated here and asserted by ar0x_installer.py.
import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    color: "#07090F"
    anchors.fill: parent

    property int slide: 0
    property var titles: [
        "Welcome to ar0x",
        "Developers, Wayland, root",
        "Cyberpunk / Dark-Hacker",
        "Almost there"
    ]
    property var bodies: [
        "ar0x 0.1.0 (ar0x root) — an Arch-based developer distribution.",
        "Hyprland 0.57 on Wayland, stock linux-lts, GRUB, zsh, and a 2 GB ISO.",
        "Void #07090F, cyan #00E5FF, magenta #FF2E88, lime #A8FF60.",
        "The installer is copying the live system. Do not power off the machine."
    ]

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 8
        color: "#00E5FF"
    }

    Image {
        id: logo
        source: "ar0x-logo.png"
        anchors.top: parent.top
        anchors.topMargin: 48
        anchors.horizontalCenter: parent.horizontalCenter
        width: 128
        height: 128
        fillMode: Image.PreserveAspectFit
    }

    Text {
        id: title
        anchors.top: logo.bottom
        anchors.topMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.titles[root.slide]
        color: "#00E5FF"
        font.pixelSize: 30
        font.bold: true
    }

    Text {
        id: body
        anchors.top: title.bottom
        anchors.topMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(720, parent.width - 96)
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        text: root.bodies[root.slide]
        color: "#D7E0EE"
        font.pixelSize: 17
    }

    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        anchors.horizontalCenter: parent.horizontalCenter
        text: "ar0x  //  AR0X ROOT  //  Developer Edition"
        color: "#6B7891"
        font.pixelSize: 14
    }

    Timer {
        interval: 9000
        running: true
        repeat: true
        onTriggered: root.slide = (root.slide + 1) % root.titles.length
    }

    function onActivate() { root.slide = 0 }
    function onLeave() {}
}
