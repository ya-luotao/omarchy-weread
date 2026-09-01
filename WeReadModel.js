// WeReadModel.js — parsing and formatting for 微信读书 reading stats.
// All durations from the API are SECONDS (see readdata.md); never minutes.

// "3小时12分钟" / "45分钟" / "0分钟"
function fmtDuration(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.round((s % 3600) / 60)
  if (h > 0 && m > 0) return h + "小时" + m + "分钟"
  if (h > 0) return h + "小时"
  return m + "分钟"
}

// Short form for tooltips: "3h12m" / "45m"
function fmtShort(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.round((s % 3600) / 60)
  if (h > 0) return h + "h" + (m > 0 ? m + "m" : "")
  return m + "m"
}

function emptyWeek() {
  return {
    ok: false,
    errcode: -1,
    errmsg: "",
    totalReadTime: 0,
    readDays: 0,
    dayAverage: 0,
    compare: null,
    days: [],      // 7 entries Mon..Sun: { seconds, label, isToday }
    books: [],     // { title, author, readTime }
    todaySeconds: 0
  }
}

var DAY_LABELS = ["一", "二", "三", "四", "五", "六", "日"]

function mondayOf(date) {
  var d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  var dow = (d.getDay() + 6) % 7 // Monday = 0
  d.setDate(d.getDate() - dow)
  return d
}

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() &&
         a.getMonth() === b.getMonth() &&
         a.getDate() === b.getDate()
}

// Parse a /readdata/detail?mode=weekly response body (as text).
function parseWeekly(text) {
  var w = emptyWeek()
  if (!text) return w
  var d
  try { d = JSON.parse(text) } catch (e) { return w }

  w.errcode = Number(d.errcode || 0)
  w.errmsg = String(d.errmsg || "")
  if (w.errcode !== 0) return w
  w.ok = true

  w.totalReadTime = Number(d.totalReadTime || 0)
  w.readDays = Number(d.readDays || 0)
  w.dayAverage = Number(d.dayAverageReadTime || 0)
  w.compare = (d.compare === undefined || d.compare === null) ? null : Number(d.compare)

  // readTimes: { bucketStartTimestamp: seconds }, weekly mode buckets by day.
  var buckets = d.readTimes || {}
  var monday = mondayOf(new Date())
  var today = new Date()
  var days = []
  for (var i = 0; i < 7; i++) {
    var day = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)
    var secs = 0
    for (var key in buckets) {
      var bucketDate = new Date(Number(key) * 1000)
      if (sameDay(bucketDate, day)) { secs += Number(buckets[key]) || 0 }
    }
    days.push({
      seconds: secs,
      label: DAY_LABELS[i],
      isToday: sameDay(day, today),
      future: day > today
    })
  }
  w.days = days
  w.todaySeconds = days[((today.getDay() + 6) % 7)].seconds

  var longest = d.readLongest || []
  var books = []
  for (var j = 0; j < longest.length && books.length < 5; j++) {
    var entry = longest[j]
    var title = null, author = ""
    if (entry.book) {
      title = entry.book.title
      author = entry.book.author || ""
    } else if (entry.albumInfo) {
      title = entry.albumInfo.title
      author = "有声书"
    }
    if (!title) continue
    books.push({ title: String(title), author: String(author), readTime: Number(entry.readTime || 0) })
  }
  w.books = books

  return w
}

// Hero line under the title: "本周 3小时12分钟 · 4天 · 日均48分钟 ↑20%"
function weekSummary(w) {
  if (!w.ok) return w.errmsg || "暂无数据"
  var s = "本周 " + fmtDuration(w.totalReadTime) + " · " + w.readDays + "天 · 日均" + fmtDuration(w.dayAverage)
  if (w.compare !== null && isFinite(w.compare)) {
    var pct = Math.round(Math.abs(w.compare) * 100)
    if (pct > 0) s += (w.compare >= 0 ? " ↑" : " ↓") + pct + "%"
  }
  return s
}
