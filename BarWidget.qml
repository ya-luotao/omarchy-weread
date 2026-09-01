import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "WeReadModel.js" as Model

// WeRead bar widget: an open-book glyph in the bar carrying your reading
// life. Click for the panel — four period views (week / month / year / all
// time) with matching bar charts, the books currently in progress, a popular
// highlight to sit with, and the lifetime numbers. Data comes from the
// WeRead agent API via tools/weread-sync; the last good bundle is cached on
// disk so the bar never starts blank.
Panel {
  id: root
  moduleName: "luotao.weread"
  ipcTarget: "luotao.weread"
  manageIpc: false

  readonly property string toolPath: String(Qt.resolvedUrl("tools/weread-sync")).replace(/^file:\/\//, "")
  readonly property string cachePath: Quickshell.env("XDG_STATE_HOME") !== ""
    ? Quickshell.env("XDG_STATE_HOME") + "/omarchy/weread/bundle.json"
    : Quickshell.env("HOME") + "/.local/state/omarchy/weread/bundle.json"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  property var bundle: Model.emptyBundle()
  property int lastFetchMs: 0
  property var quotePick: null

  property string period: String(setting("defaultPeriod", "weekly"))
  readonly property var view: Model.periodView(bundle, period)
  readonly property int streak: bundle.ok ? Model.streakDays(bundle) : 0
  readonly property int todaySeconds: bundle.ok ? Model.todaySeconds(bundle) : 0

  readonly property string tooltip: bundle.ok
    ? "微信读书 · 今天 " + Model.fmtShort(todaySeconds) + " · 本周 " +
      Model.fmtShort(Model.periodView(bundle, "weekly").totalReadTime) +
      (streak > 0 ? " · 连续" + streak + "天" : "")
    : (bundle.errmsg !== "" ? "微信读书 — " + bundle.errmsg : "微信读书")

  function refresh() {
    if (!fetchProc.running) fetchProc.running = true
  }

  function choosePeriod(key) {
    period = key
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry.defaultPeriod = key
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function pickQuote() {
    var items = bundle.quotes.items
    quotePick = items && items.length > 0
      ? items[Math.floor(Math.random() * items.length)] : null
  }

  onOpenedChanged: {
    if (opened) {
      cacheFile.reload()
      pickQuote()
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
      var b = Model.parseBundle(text())
      if (b.ok || b.errcode !== -1) root.bundle = b
    }
    onFileChanged: reload()
  }

  Process {
    id: fetchProc
    command: [root.toolPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastFetchMs = Date.now()
        var b = Model.parseBundle(text)
        if (b.ok || b.errcode !== -1) root.bundle = b
      }
    }
    onExited: root.lastFetchMs = Date.now()
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
        ok: root.bundle.ok,
        todaySeconds: root.todaySeconds,
        streakDays: root.streak,
        weekSeconds: Model.periodView(root.bundle, "weekly").totalReadTime,
        shelfCount: root.bundle.shelf ? root.bundle.shelf.total : 0,
        noteCount: root.bundle.notes ? root.bundle.notes.totalCount : 0,
        reading: root.bundle.reading.map(function(b) { return { title: b.title, progress: b.progress } })
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
        // An open book: two pages falling away from the spine. A dot on the
        // spine once reading has happened today.
        Canvas {
          anchors.centerIn: parent
          width: Style.space(14)
          height: Style.space(14)

          readonly property color stroke: root.barForeground
          readonly property bool readToday: root.bundle.ok && root.todaySeconds > 0
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
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTextKey: function(text) {
        var k = String(text || "").toLowerCase()
        var keys = Model.PERIOD_KEYS
        var idx = ["1", "2", "3", "4"].indexOf(k)
        if (idx !== -1) root.choosePeriod(keys[idx])
        else if (k === "r") root.refresh()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "微信读书"
          meta: !root.bundle.ok
            ? (fetchProc.running ? "加载中…" : (root.bundle.errmsg || "暂无数据"))
            : Model.periodSummary(root.view) + (root.streak > 1 ? " · 连续" + root.streak + "天" : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // Setup hint when the API key is missing.
        Text {
          width: parent.width
          visible: root.bundle.errcode === 4010
          text: "获取 API Key：weread.qq.com/r/weread-skills\n然后任选其一：\n· export WEREAD_API_KEY=wrk-…\n· 写入 ~/.config/omarchy/weread/api-key"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // Period tabs.
        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: root.bundle.ok

          Repeater {
            model: Model.PERIOD_KEYS

            Button {
              required property string modelData
              text: Model.PERIOD_TITLES[modelData]
              bordered: true
              selected: root.period === modelData
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.choosePeriod(modelData)
            }
          }
        }

        // Friend ranking, current week only.
        Text {
          width: parent.width
          visible: root.period === "weekly" && !!root.view.rank
          text: root.view.rank || ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // The period at a glance: bars whose granularity matches the tab —
        // days for week and month, months for year, years for all time.
        Column {
          id: chart
          width: parent.width
          spacing: Style.space(4)
          visible: root.view.ok && root.view.series.length > 0

          Row {
            width: parent.width
            spacing: root.view.series.length > 20 ? Style.space(1) : Style.space(3)

            Repeater {
              model: root.view.series

              Column {
                required property var modelData
                readonly property real share: root.view.seriesMax > 0
                  ? modelData.seconds / root.view.seriesMax : 0
                width: (parent.width - parent.spacing * (root.view.series.length - 1)) / root.view.series.length
                spacing: Style.space(3)

                Item {
                  width: parent.width
                  height: Style.space(34)

                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(Style.space(2), parent.width * 0.6)
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
                  visible: text !== ""
                  text: modelData.label
                  color: modelData.isToday ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.view.preferLine !== ""
          text: root.view.preferLine
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // Currently reading: progress bars for the shelf's most recent books.
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.bundle.reading.length > 0

          Text {
            text: "正在读"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.bundle.reading

            Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(2)

              Row {
                width: parent.width
                spacing: Style.space(8)

                Text {
                  id: bookTitle
                  width: parent.width - pct.implicitWidth - parent.spacing
                  text: modelData.title + (modelData.author !== "" ? " · " + modelData.author : "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  id: pct
                  text: modelData.progress + "%"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Rectangle {
                width: parent.width
                height: Style.space(3)
                radius: Style.space(1.5)
                color: root.foreground
                opacity: 0.15

                Rectangle {
                  width: Math.max(Style.space(3), parent.width * Math.min(100, modelData.progress) / 100)
                  height: parent.height
                  radius: parent.radius
                  color: Color.accent
                  opacity: 0.9
                }
              }
            }
          }
        }

        // Where the time went in this period.
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.view.books.length > 0

          Text {
            text: "读得最多"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.view.books.slice(0, 3)

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

        // A popular highlight from the book at the top of the week —
        // re-rolled every time the panel opens.
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.quotePick !== null

          Text {
            text: "热门划线" + (root.bundle.quotes.bookTitle !== "" ? " · 《" + root.bundle.quotes.bookTitle + "》" : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            text: root.quotePick ? "“" + root.quotePick.text + "”" : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.quotePick && root.quotePick.count > 0
            text: root.quotePick ? root.quotePick.count + " 人划过这句" : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // Lifetime numbers + shelf and notes footprint.
        Text {
          width: parent.width
          visible: root.period === "overall" && root.view.readStat.length > 0
          text: root.view.readStat.map(function(s) { return s.stat + " " + s.counts }).join(" · ")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.bundle.ok
          text: {
            var parts = []
            if (root.bundle.shelf) parts.push("书架 " + root.bundle.shelf.total)
            if (root.bundle.notes && root.bundle.notes.totalCount > 0)
              parts.push("笔记 " + root.bundle.notes.totalCount + "条")
            if (root.bundle.recommend.length > 0)
              parts.push("推荐《" + root.bundle.recommend[0].title + "》")
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "1-4 周期 · R 刷新 · Esc 关闭"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
