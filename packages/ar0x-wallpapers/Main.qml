/***************************************************************************
 * /usr/share/sddm/themes/ar0x/Main.qml
 * ar0x 0.1.0 "Neon Root" — SDDM 0.21 Qt6 greeter theme.
 *
 * Qt6 SAFETY: only `QtQuick` and `SddmComponents 2.0` are imported. No
 * QtGraphicalEffects (Qt5-only), no QtMultimedia, no custom QML modules, no
 * versioned Qt5Compat imports. Connections use the Qt6 `function onX()` form.
 * SddmComponents ships with the Arch sddm package (qt6-declarative).
 *
 * Palette (config/versions.env, ADR-015) — mirrored here because SDDM's
 * ThemeConfig only reliably exposes `background`. tools/configure-desktop.sh
 * --check asserts every hex below equals the corresponding AR0X_* pin:
 *   #07090F void  #11151F surface  #00E5FF cyan  #FF2E88 magenta
 *   #A8FF60 lime  #D7E0EE text     #6B7891 muted #FF5C57 alert
 ***************************************************************************/

import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
    id: root
    width: 640
    height: 480
    color: "#07090F"

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    property int sessionIndex: session.index
    property string accent: "#00E5FF"
    property string magenta: "#FF2E88"
    property string surface: "#11151F"
    property string fg: "#D7E0EE"
    property string muted: "#6B7891"
    property string alert: "#FF5C57"

    TextConstants { id: textConstants }

    Connections {
        target: sddm
        function onLoginSucceeded() {
            errorMessage.color = "#A8FF60"
            errorMessage.text = textConstants.loginSucceeded
        }
        function onLoginFailed() {
            password.text = ""
            errorMessage.color = "#FF5C57"
            errorMessage.text = textConstants.loginFailed
        }
        function onInformationMessage(message) {
            errorMessage.color = "#FF5C57"
            errorMessage.text = message
        }
    }

    // Background is drawn only on the primary screen by SddmComponents.
    Background {
        anchors.fill: parent
        source: Qt.resolvedUrl(config.background)
        fillMode: Image.PreserveAspectCrop
    }

    // Dark scrim so the neon panel stays legible over any wallpaper.
    Rectangle {
        anchors.fill: parent
        color: "#9907090F"
    }

    Clock {
        id: clock
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        color: "#00E5FF"
        timeFont.family: "JetBrainsMono Nerd Font"
    }

    // --- Central login panel ------------------------------------------------
    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.max(420, form.implicitWidth + 64)
        height: Math.max(300, form.implicitHeight + 64)
        color: "#EE11151F"
        border.color: "#00E5FF"
        border.width: 2
        radius: 6

        Column {
            id: form
            anchors.centerIn: parent
            spacing: 12
            width: 360

            Text {
                width: parent.width
                text: "ar0x"
                color: "#00E5FF"
                font.pixelSize: 46
                font.bold: true
                font.family: "JetBrainsMono Nerd Font"
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: "0.1.0  //  NEON ROOT"
                color: "#FF2E88"
                font.pixelSize: 12
                font.family: "JetBrainsMono Nerd Font"
                horizontalAlignment: Text.AlignHCenter
            }
            Rectangle {
                width: parent.width
                height: 1
                color: "#6B7891"
            }

            // Username
            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: textConstants.userName
                    color: "#D7E0EE"
                    font.bold: true
                    font.pixelSize: 12
                }
                TextBox {
                    id: name
                    width: parent.width
                    height: 34
                    text: userModel.lastUser
                    font.pixelSize: 14
                    color: "#07090F"
                    textColor: "#D7E0EE"
                    borderColor: "#6B7891"
                    focusColor: "#00E5FF"
                    hoverColor: "#00E5FF"
                    KeyNavigation.backtab: rebootButton
                    KeyNavigation.tab: password
                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(name.text, password.text, sessionIndex)
                            event.accepted = true
                        }
                    }
                }
            }

            // Password
            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: textConstants.password
                    color: "#D7E0EE"
                    font.bold: true
                    font.pixelSize: 12
                }
                PasswordBox {
                    id: password
                    width: parent.width
                    height: 34
                    font.pixelSize: 14
                    color: "#07090F"
                    textColor: "#D7E0EE"
                    borderColor: "#6B7891"
                    focusColor: "#00E5FF"
                    hoverColor: "#00E5FF"
                    KeyNavigation.backtab: name
                    KeyNavigation.tab: session
                    Keys.onPressed: function (event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sddm.login(name.text, password.text, sessionIndex)
                            event.accepted = true
                        }
                    }
                }
            }

            // Session + keyboard layout
            Row {
                width: parent.width
                spacing: 8
                Column {
                    width: (parent.width - 8) * 0.65
                    spacing: 4
                    Text {
                        text: textConstants.session
                        color: "#D7E0EE"
                        font.bold: true
                        font.pixelSize: 12
                    }
                    ComboBox {
                        id: session
                        width: parent.width
                        height: 32
                        font.pixelSize: 13
                        color: "#07090F"
                        textColor: "#D7E0EE"
                        borderColor: "#6B7891"
                        focusColor: "#00E5FF"
                        menuColor: "#11151F"
                        arrowColor: "#00E5FF"
                        model: sessionModel
                        index: sessionModel.lastIndex
                        KeyNavigation.backtab: password
                        KeyNavigation.tab: layoutBox
                    }
                }
                Column {
                    width: (parent.width - 8) * 0.35
                    spacing: 4
                    visible: keyboard.enabled && keyboard.layouts.length > 0
                    Text {
                        text: textConstants.layout
                        color: "#D7E0EE"
                        font.bold: true
                        font.pixelSize: 12
                    }
                    LayoutBox {
                        id: layoutBox
                        width: parent.width
                        height: 32
                        font.pixelSize: 13
                        color: "#07090F"
                        textColor: "#D7E0EE"
                        borderColor: "#6B7891"
                        focusColor: "#00E5FF"
                        menuColor: "#11151F"
                        arrowColor: "#00E5FF"
                        KeyNavigation.backtab: session
                        KeyNavigation.tab: loginButton
                    }
                }
            }

            Text {
                id: errorMessage
                width: parent.width
                text: textConstants.prompt
                color: "#6B7891"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            // Actions
            Row {
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                Button {
                    id: loginButton
                    text: textConstants.login
                    width: 110
                    color: "#11151F"
                    activeColor: "#11151F"
                    pressedColor: "#00E5FF"
                    textColor: "#00E5FF"
                    borderColor: "#00E5FF"
                    onClicked: sddm.login(name.text, password.text, sessionIndex)
                    KeyNavigation.backtab: layoutBox
                    KeyNavigation.tab: shutdownButton
                }
                Button {
                    id: shutdownButton
                    text: textConstants.shutdown
                    width: 110
                    color: "#11151F"
                    activeColor: "#11151F"
                    pressedColor: "#6B7891"
                    textColor: "#D7E0EE"
                    borderColor: "#6B7891"
                    onClicked: sddm.powerOff()
                    KeyNavigation.backtab: loginButton
                    KeyNavigation.tab: rebootButton
                }
                Button {
                    id: rebootButton
                    text: textConstants.reboot
                    width: 110
                    color: "#11151F"
                    activeColor: "#11151F"
                    pressedColor: "#FF2E88"
                    textColor: "#FF2E88"
                    borderColor: "#FF2E88"
                    onClicked: sddm.reboot()
                    KeyNavigation.backtab: shutdownButton
                    KeyNavigation.tab: name
                }
            }
        }
    }

    Component.onCompleted: {
        if (name.text === "")
            name.focus = true
        else
            password.focus = true
    }
}
