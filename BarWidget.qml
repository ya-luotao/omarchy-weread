import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "WeReadModel.js" as Model

// WeRead bar widget: an open-book glyph in the bar carrying this week's
// reading life. Click for the panel — daily bars and the books the time
// actually went to. Data comes from the WeRead agent API via tools/weread-api;
// the last good response is cached on disk so the bar never starts blank.
Panel {
  id: root
  moduleName: "luotao.weread"
  ipcTarget: "luotao.weread"
  manageIpc: false

  readonly property string toolPath: String(Qt.resolvedUrl("tools/weread-api")).replace(/^file:\/\//, "")
  readonly property string cachePath: Quickshell.env("XDG_STATE_HOME") !== ""
    ? Quickshell.env("XDG_STATE_HOME") + "/omarchy/weread/weekly.json"
    : Quickshell.env("HOME") + "/.local/state/omarchy/weread/weekly.json"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  property var week: Model.emptyWeek()
  property bool fetching: false
  property int lastFetchMs: 0

  readonly property string tooltip: week.ok
    ? "微信读书 · 今天 " + Model.fmtShort(week.todaySeconds) + " · 本周 " + Model.fmtShort(week.totalReadTime)
    : (week.errmsg !== "" ? "微信读书 — " + week.errmsg : "微信读书")

  function refresh() {
    if (fetchProc.running) return
    fetchProc.running = true
  }

  // Fresh data when it is actually looked at; the cache fills the gap.
  onOpenedChanged: {
    if (opened) {
      cacheFile.reload()
      if (Date.now() - lastFetchMs > 5 * 60 * 1000) refresh()
    }
  }

  Component.onCompleted: refresh()

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var w = Model.parseWeekly(text())
      if (w.ok) root.week = w
    }
    onFileChanged: reload()
  }

  Process {
    id: fetchProc
    command: [root.toolPath, "/readdata/detail", '{"mode":"weekly"}', "weekly"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastFetchMs = Date.now()
        var w = Model.parseWeekly(text)
        if (w.ok || w.errcode !== -1) root.week = w // keep cache over a local parse failure
      }
    }
    onExited: function(exitCode) { root.lastFetchMs = Date.now() }
  }

  Timer {
    interval: Math.max(5, Number(setting("refreshMinutes", 15))) * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function status(): string {
      return JSON.stringify({
        ok: root.week.ok,
        todaySeconds: root.week.todaySeconds,
        weekSeconds: root.week.totalReadTime,
        weekDays: root.week.readDays,
        topBook: root.week.books.length > 0 ? root.week.books[0].title : null
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip

    iconComponent: Component {
      Item {
        // An open book: two pages falling away from the spine. The spine
        // fills in accent once reading has happened today.
        Canvas {
          anchors.centerIn: parent
          width: Style.space(14)
          height: Style.space(14)

          readonly property color stroke: root.barForeground
          readonly property bool readToday: root.week.ok && root.week.todaySeconds > 0
          onStrokeChanged: requestPaint()
          onReadTodayChanged: requestPaint()

          onPaint: {
            var w = width, h = height
            var ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = stroke
            ctx.lineWidth = 1.5
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.moveTo(w * 0.5, h * 0.24)
            ctx.quadraticCurveTo(w * 0.27, h * 0.06, w * 0.06, h * 0.18)
            ctx.lineTo(w * 0.06, h * 0.80)
            ctx.quadraticCurveTo(w * 0.27, h * 0.66, w * 0.5, h * 0.84)
            ctx.quadraticCurveTo(w * 0.73, h * 0.66, w * 0.94, h * 0.80)
            ctx.lineTo(w * 0.94, h * 0.18)
            ctx.quadraticCurveTo(w * 0.73, h * 0.06, w * 0.5, h * 0.24)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(w * 0.5, h * 0.24)
            ctx.lineTo(w * 0.5, h * 0.84)
            ctx.stroke()
            if (readToday) {
              ctx.fillStyle = Color.accent
              ctx.beginPath()
              ctx.arc(w * 0.5, h * 0.54, Math.max(1.2, w * 0.08), 0, Math.PI * 2, false)
              ctx.fill()
            }
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(440))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTextKey: function(text) {
        var k = String(text || "").toLowerCase()
        if (k === "r") root.refresh()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "微信读书"
          meta: root.fetching && !root.week.ok ? "加载中…" : Model.weekSummary(root.week)
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // Setup hint when the API key is missing — the one thing the user
        // has to do before any of this works.
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.week.errcode === 4010

          Text {
            width: parent.width
            text: "获取 API Key：weread.qq.com/r/weread-skills\n然后任选其一：\n· export WEREAD_API_KEY=wrk-…\n· 写入 ~/.config/omarchy/weread/api-key"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        // The week at a glance: seven small bars, today in accent.
        Column {
          id: weekView
          width: parent.width
          spacing: Style.space(4)
          visible: root.week.ok

          readonly property int weekMax: {
            var max = 0
            for (var i = 0; i < root.week.days.length; i++)
              max = Math.max(max, root.week.days[i].seconds)
            return max
          }

          Text {
            text: "本周 · " + Model.fmtDuration(root.week.totalReadTime)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.week.days

              Column {
                required property var modelData
                readonly property real share: weekView.weekMax > 0
                  ? modelData.seconds / weekView.weekMax : 0
                spacing: Style.space(3)

                Item {
                  width: Style.space(18)
                  height: Style.space(34)

                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(10)
                    height: Math.max(Style.space(2), Math.round(parent.height * share))
                    radius: Style.space(2)
                    color: modelData.isToday ? Color.accent : root.foreground
                    opacity: modelData.seconds > 0
                      ? (modelData.isToday ? 0.9 : 0.45)
                      : (modelData.future ? 0.08 : 0.15)
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: modelData.label
                  color: modelData.isToday ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }

        // Where the time went: this week's most-read books.
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.week.ok && root.week.books.length > 0

          Text {
            text: "读得最多"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.week.books

            Row {
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(8)

              Text {
                id: num
                text: (index + 1) + "."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                width: parent.width - num.implicitWidth - time.implicitWidth - parent.spacing * 2
                text: modelData.title + (modelData.author !== "" ? " · " + modelData.author : "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                id: time
                text: Model.fmtShort(modelData.readTime)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "R 刷新 · 中键刷新 · Esc 关闭"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
