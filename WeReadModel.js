// WeReadModel.js — parsing and formatting for 微信读书 reading stats.
// All durations from the API are SECONDS (see readdata.md); never minutes.

// ---------- formatting ----------

// "3小时12分钟" / "45分钟" / "0分钟"
function fmtDuration(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.round((s % 3600) / 60)
  if (h > 0 && m > 0) return h + "小时" + m + "分钟"
  if (h > 0) return h + "小时"
  return m + "分钟"
}

// Short form for tooltips and lists: "3h12m" / "45m"
function fmtShort(seconds) {
  var s = Math.max(0, Math.round(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.round((s % 3600) / 60)
  if (h > 0) return h + "h" + (m > 0 ? m + "m" : "")
  return m + "m"
}

function fmtDate(ts) {
  if (!ts) return ""
  var d = new Date(Number(ts) * 1000)
  return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2)
}

// ---------- helpers ----------

var DAY_LABELS = ["一", "二", "三", "四", "五", "六", "日"]

function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() &&
         a.getMonth() === b.getMonth() &&
         a.getDate() === b.getDate()
}

function sameMonth(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
}

function mondayOf(date) {
  var d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7))
  return d
}

function bucketSeconds(readTimes, pred) {
  var secs = 0
  for (var key in (readTimes || {})) {
    if (pred(new Date(Number(key) * 1000))) secs += Number(readTimes[key]) || 0
  }
  return secs
}

// ---------- series builders (one bar row per period granularity) ----------

function weeklySeries(readTimes) {
  var monday = mondayOf(new Date())
  var today = new Date()
  var out = []
  for (var i = 0; i < 7; i++) {
    var day = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)
    out.push({
      seconds: bucketSeconds(readTimes, function(d) { return sameDay(d, day) }),
      label: DAY_LABELS[i],
      isToday: sameDay(day, today),
      future: day > today
    })
  }
  return out
}

function monthlySeries(readTimes, baseTime) {
  var base = baseTime ? new Date(Number(baseTime) * 1000) : new Date()
  var year = base.getFullYear(), month = base.getMonth()
  var days = new Date(year, month + 1, 0).getDate()
  var today = new Date()
  var out = []
  for (var d = 1; d <= days; d++) {
    var day = new Date(year, month, d)
    out.push({
      seconds: bucketSeconds(readTimes, function(x) { return sameDay(x, day) }),
      label: d % 5 === 1 || d === days ? String(d) : "",
      isToday: sameDay(day, today),
      future: day > today
    })
  }
  return out
}

function annuallySeries(readTimes) {
  var now = new Date()
  var year = now.getFullYear()
  var out = []
  for (var m = 0; m < 12; m++) {
    out.push({
      seconds: bucketSeconds(readTimes, function(d) { return d.getFullYear() === year && d.getMonth() === m }),
      label: (m + 1) + "月",
      isToday: now.getMonth() === m,
      future: m > now.getMonth()
    })
  }
  return out
}

function overallSeries(readTimes) {
  var byYear = {}
  for (var key in (readTimes || {})) {
    var d = new Date(Number(key) * 1000)
    var y = d.getFullYear()
    byYear[y] = (byYear[y] || 0) + (Number(readTimes[key]) || 0)
  }
  var years = Object.keys(byYear).sort()
  var thisYear = new Date().getFullYear()
  return years.map(function(y) {
    return { seconds: byYear[y], label: String(y).slice(2) + "'", isToday: Number(y) === thisYear, future: false }
  })
}

// ---------- streak ----------

// Consecutive days with >= 60s reading (the server's 有效阅读 rule), ending
// today — or yesterday, if today hasn't crossed the minute mark yet. Built
// from this + last month's daily buckets (best available granularity).
function streakDays(bundle) {
  var cur = (bundle.periods.monthly || {}).readTimes || {}
  var prev = (bundle.periods.monthlyPrev || {}).readTimes || {}
  function secondsOn(day) {
    return bucketSeconds(cur, function(d) { return sameDay(d, day) }) +
           bucketSeconds(prev, function(d) { return sameDay(d, day) })
  }
  var day = new Date()
  if (secondsOn(day) < 60) day = new Date(day.getFullYear(), day.getMonth(), day.getDate() - 1)
  var streak = 0
  while (secondsOn(day) >= 60 && streak < 70) {
    streak++
    day = new Date(day.getFullYear(), day.getMonth(), day.getDate() - 1)
  }
  return streak
}

// ---------- bundle parsing ----------

var PERIOD_KEYS = ["weekly", "monthly", "annually", "overall"]
var PERIOD_TITLES = { weekly: "本周", monthly: "本月", annually: "今年", overall: "总计" }

function emptyBundle() {
  return { ok: false, errcode: -1, errmsg: "", fetchedAt: 0, periods: {},
           shelf: null, notes: null, reading: [], quotes: { bookTitle: "", items: [] },
           recommend: [] }
}

function parseBundle(text) {
  var b = emptyBundle()
  if (!text) return b
  var d
  try { d = JSON.parse(text) } catch (e) { return b }
  if (d.errcode && Number(d.errcode) !== 0) {
    b.errcode = Number(d.errcode)
    b.errmsg = String(d.errmsg || "")
    return b
  }
  b.ok = d.ok === true
  b.fetchedAt = Number(d.fetchedAt || 0)
  b.periods = d.periods || {}
  b.shelf = d.shelf || null
  b.notes = d.notes || null
  b.reading = d.reading || []
  b.quotes = d.quotes || { bookTitle: "", items: [] }
  b.recommend = d.recommend || []
  return b
}

// Everything the panel needs to render one period tab.
function periodView(bundle, key) {
  var p = (bundle.periods || {})[key]
  var v = { ok: false, title: PERIOD_TITLES[key] || key, totalReadTime: 0, readDays: 0,
            dayAverage: 0, compare: null, rank: null, preferLine: "", books: [],
            series: [], seriesMax: 0, readStat: [] }
  if (!p || Number(p.errcode || 0) !== 0) return v
  v.ok = true
  v.totalReadTime = Number(p.totalReadTime || 0)
  v.readDays = Number(p.readDays || 0)
  v.dayAverage = Number(p.dayAverage || 0)
  v.compare = (p.compare === undefined || p.compare === null) ? null : Number(p.compare)
  v.rank = p.rank || null
  v.books = p.books || []
  v.readStat = p.readStat || []
  var words = []
  if (p.preferTimeWord) words.push(p.preferTimeWord)
  if (p.preferCategoryWord) words.push(p.preferCategoryWord)
  v.preferLine = words.join(" · ")

  if (key === "weekly") v.series = weeklySeries(p.readTimes)
  else if (key === "monthly") v.series = monthlySeries(p.readTimes, p.baseTime)
  else if (key === "annually") v.series = annuallySeries(p.readTimes)
  else v.series = overallSeries(p.readTimes)

  var max = 0
  for (var i = 0; i < v.series.length; i++) max = Math.max(max, v.series[i].seconds)
  v.seriesMax = max
  return v
}

// Hero meta line: "本周 3小时12分钟 · 4天 · 日均48分钟 ↑20%"
function periodSummary(view) {
  if (!view.ok) return "暂无数据"
  var s = view.title + " " + fmtDuration(view.totalReadTime)
  if (view.readDays > 0) s += " · " + view.readDays + "天"
  if (view.dayAverage >= 60 && view.title !== "总计") s += " · 日均" + fmtDuration(view.dayAverage)
  if (view.compare !== null && isFinite(view.compare) && view.compare > -1) {
    var pct = Math.round(Math.abs(view.compare) * 100)
    if (pct > 0) s += (view.compare >= 0 ? " ↑" : " ↓") + pct + "%"
  }
  return s
}

function todaySeconds(bundle) {
  var w = (bundle.periods || {}).weekly
  if (!w) return 0
  var today = new Date()
  return bucketSeconds(w.readTimes, function(d) { return sameDay(d, today) })
}
