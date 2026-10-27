import fs from "node:fs"
import path from "node:path"

const dir = process.argv[2]
const days = Number(process.argv[3] ?? 45)
if (!dir || !fs.existsSync(dir)) throw new Error(`Data dir not found: ${dir}`)

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR

const firstTs = (prefix) => {
  const files = fs.readdirSync(dir).filter((f) => f.startsWith(`${prefix}_`) && f.endsWith(".ndjson") && !f.includes("synthetic"))
  const ts = files.map((f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8").split("\n")[0]).ts)
  return ts.length ? Math.min(...ts) : Date.now()
}

const end = Math.min(firstTs("cpu"), firstTs("memory")) - 5000
const start = end - days * DAY

let seed = 42
const rand = () => ((seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296)
const noise = (amp) => (rand() * 2 - 1) * amp

const spikes = Array.from({ length: 10 }, () => ({ at: start + rand() * (end - start), len: (0.5 + rand() * 3) * HOUR, mag: 0.6 + rand() * 1.4 }))
const spikeAt = (t) => spikes.reduce((s, { at, len, mag }) => (t >= at && t <= at + len ? s + mag * Math.sin(((t - at) / len) * Math.PI) : s), 0)

const timestamps = []
for (let t = start; t < end; t += t < end - DAY ? 5 * MIN : MIN) timestamps.push(Math.round(t))

const dayStr = (t) => new Date(t).toISOString().slice(0, 10).replace(/-/g, "")
const buckets = new Map()
const push = (prefix, t, rows) => {
  const key = `${prefix}_${dayStr(t)}_synthetic.ndjson`
  if (!buckets.has(key)) buckets.set(key, { first: t, lines: [] })
  buckets.get(key).lines.push(...rows.map((r) => JSON.stringify(r)))
}

let cpuUser = 50
let cpuSys = 10
let prevT = start
let peak = 0

for (const t of timestamps) {
  const progress = (t - start) / (end - start)
  const daily = Math.sin(((t % DAY) / DAY) * 2 * Math.PI - Math.PI / 2) * 0.5 + 0.5
  const weekday = new Date(t).getUTCDay()
  const weekly = weekday === 0 || weekday === 6 ? 0.6 : 1
  const spike = spikeAt(t)

  const cores = Math.max(0.02, (0.08 + 0.45 * daily * weekly + 0.5 * spike + noise(0.04)) * (0.8 + 0.4 * progress))
  const dt = (t - prevT) / 1000
  cpuUser += cores * 0.78 * dt
  cpuSys += cores * 0.22 * dt
  prevT = t
  push("cpu", t, [
    { ts: t, metric: "used_cpu_sys", value: Number(cpuSys.toFixed(6)) },
    { ts: t, metric: "used_cpu_user", value: Number(cpuUser.toFixed(6)) },
  ])

  const keys = Math.round(40_000 + 140_000 * progress + 15_000 * daily * weekly + 25_000 * spike + noise(1500))
  const bytesPerKey = 620 + 80 * Math.sin(progress * 6) + noise(10)
  const dataset = keys * bytesPerKey
  const overhead = 1_200_000 + keys * 72 + noise(50_000)
  const used = dataset + overhead
  peak = Math.max(peak, used)
  const active = used * (1.04 + 0.03 * daily + noise(0.005))
  const resident = active * (1.08 + 0.06 * progress + noise(0.01))
  push("memory", t, [
    ["used_memory", Math.round(used)],
    ["allocator_active", Math.round(active)],
    ["allocator_resident", Math.round(resident)],
    ["peak_allocated", Math.round(peak)],
    ["dataset_bytes", Math.round(dataset)],
    ["overhead_total", Math.round(overhead)],
    ["dataset_percentage", Number(((dataset / used) * 100).toFixed(2))],
    ["fragmentation", Number((resident / used).toFixed(2))],
    ["fragmentation_bytes", Math.round(resident - used)],
    ["allocator_rss_ratio", Number((resident / active).toFixed(2))],
    ["keys_count", keys],
    ["keys_bytes_per_key", dataset / keys],
  ].map(([metric, value]) => ({ ts: t, metric, value })))
}

for (const [name, { first, lines }] of buckets) {
  const file = path.join(dir, name)
  fs.writeFileSync(file, lines.join("\n") + "\n")
  const when = new Date(first)
  fs.utimesSync(file, when, when)
}

console.log(`Wrote ${buckets.size} files, ${timestamps.length} samples, ${new Date(start).toISOString()} → ${new Date(end).toISOString()}`)
