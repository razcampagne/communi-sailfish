/*
  Copyright (C) 2013-2014 Robin Burchell <robin+git@viroteck.net>
  Copyright (C) 2013-2014 J-P Nurmi <jpnurmi@gmail.com>

  You may use this file under the terms of BSD license as follows:

  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Jolla Ltd nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

import QtQuick 2.1
import Communi 3.1
import Sailfish.Silica 1.0
import Qt.labs.settings 1.0
import org.nemomobile.ngf 1.0
import org.nemomobile.notifications 1.0
import "dialogs"
import "pages"
import "cover"

ApplicationWindow {
    id: window

    property Page currentPage: pageStack.currentPage
    property IrcBuffer currentBuffer: currentPage ? currentPage.buffer || null : null

    cover: CoverPage {
        id: appCover
    }
    onApplicationActiveChanged: {
        if (window.applicationActive) {
            appCover.resetCover();
        }
    }

    Binding {
        target: MessageFormatter
        property: "baseColor"
        value: Theme.highlightColor // alternatively a bit less prominent Theme.secondaryHighlightColor
    }

    Connections {
        target: MessageStorage
        onHighlighted: {
            if (Qt.application.active) {
                activeEffect.play();
            } else {
                // Send notification
                backgroundNotification.summary = qsTr("New message")
                backgroundNotification.body = qsTr("%1: %2").arg(message.nick).arg(message.content)
                backgroundNotification.previewSummary = qsTr("New message")
                backgroundNotification.previewBody = qsTr("%1: %2").arg(message.nick).arg(message.content)
                backgroundNotification.buffer = buffer
                backgroundNotification.publish()

                // Increase highlight count on cover
                appCover.unreadHighlights += 1;
            }
        }
        onMessageCountChanged: {
            if (!window.applicationActive) {
                appCover.addActiveBuffer(bufferDisplayName);
            }
        }
    }

    NonGraphicalFeedback {
        id: activeEffect
        event: "chat_fg"
    }

    Notification {
        id: backgroundNotification
        category: "x-nemo.messaging.im"
        property IrcBuffer buffer

        onClicked: {
            bufferPage.buffer = backgroundNotification.buffer
            window.activate()
        }
    }

    initialPage: Component { Page { } } // TODO: WelcomePage

    PanelView {
        id: viewer

        anchors.fill: parent
        interactive: !!currentPage && !!currentPage.__isBufferPage

        leftPanel: BufferListPanel {
            highlighted: false // TODO
            onClicked: {
                if (buffer !== currentBuffer)
                    pageStack.replace(bufferPage, {buffer: buffer})
                hide()
            }
        }

        rightPanel: UserListPanel {
            buffer: currentBuffer
            active: !!buffer && buffer.channel && buffer.active
            onClicked: {
                var buffer = user.channel.model.add(user.name)
                pageStack.replace(bufferPage, {buffer: buffer})
                hide()
            }
        }
    }

    Component {
        id: bufferPage
        BufferPage {
            id: bp
            property bool __isBufferPage: true
            showNavigationIndicator: false
            Binding {
                target: bp.contentItem
                property: "parent"
                value: bp.status === PageStatus.Active ? viewer : bp
            }
        }
    }

    Component {
        id: ircConnection
        IrcConnection { }
    }

    IrcCommand {
        id: ircCommand
    }

    Component {
        id: connectDialog
        ConnectDialog {
            id: dialog
            onAccepted: {
                var connection = ircConnection.createObject(BufferModel)
                connection.host = dialog.host
                connection.port = dialog.port
                connection.secure = dialog.secure
                connection.nickName = dialog.nickName
                connection.realName = dialog.realName
                connection.userName = dialog.userName
                connection.password = dialog.password
                for (var i = 0; i < dialog.channels.length; ++i) {
                    var channel = dialog.channels[i].trim()
                    if (!!channel)
                        connection.sendCommand(ircCommand.createJoin(channel))
                }

                BufferModel.addConnection(connection)
                if (NetworkSession.open())
                    connection.open()

                if (!currentPage || !currentPage.__isBufferPage)
                    pageStack.replace(bufferPage, {buffer: BufferModel.models[BufferModel.models.length-1].get(0)})
            }
        }
    }

    Component {
        id: joinDialog
        JoinDialog {
            id: dialog
            onAccepted: dialog.connection.sendCommand(ircCommand.createJoin(dialog.channel, dialog.password))
        }
    }

    Component {
        id: queryDialog
        QueryDialog {
            id: dialog
            onAccepted: pageStack.replace(bufferPage, {buffer: dialog.network.add(dialog.user)})
        }
    }

    Settings {
        id: settings
        property var state
    }

    Component.onCompleted: {
        BufferModel.restoreState(settings.state)
        if (BufferModel.models.length)
            pageStack.replace(bufferPage, {buffer: BufferModel.models[0].get(0)})
        else
            pageStack.push(connectDialog) // TODO: WelcomePage instead
    }

    Component.onDestruction: settings.state = BufferModel.saveState()
}
