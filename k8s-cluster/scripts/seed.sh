#!/bin/bash
until valkey-cli -c -h valkey-demo -p 6379 ping 2>/dev/null | grep -q PONG; do sleep 2; done
# wait for cluster to be fully formed
until valkey-cli -h valkey-demo -p 6379 cluster info | grep -q "cluster_state:ok"; do
  echo "waiting for cluster..."
  sleep 3
done
echo "==> Cluster ready. Seeding..."

# --- 3000 user sessions ---
{
  for i in $(seq 1 3000); do
    sid=$(printf '%016x%016x' $((i * 6364136223846793005)) $((RANDOM * 65536 + RANDOM)))
    uid=$((RANDOM % 50000 + 1))
    ttl=$((RANDOM % 7200 + 300))
    echo "HSET session:$sid user_id $uid role user created_at $((RANDOM % 86400)) ip 10.$((RANDOM%255)).$((RANDOM%255)).$((RANDOM%255))"
    echo "EXPIRE session:$sid $ttl"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  sessions done"

# --- 500 products ---
{
  for i in $(seq 1 500); do
    echo "HSET product:$i name Product-$i price $((RANDOM % 10000 + 99)) stock $((RANDOM % 500 + 1)) views $((RANDOM % 50000 + 100)) category $((RANDOM % 20 + 1)) rating $((RANDOM % 50 + 10))"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  products done"

# --- 1000 user profiles ---
{
  for i in $(seq 1 1000); do
    echo "HSET user:$i name User-$i email user$i@example.com plan $((RANDOM % 3)) orders $((RANDOM % 200))"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  users done"

# --- 300 cache entries ---
{
  for i in $(seq 1 300); do
    echo "SET cache:query:$i result-$i EX $((RANDOM % 3600 + 60))"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  cache done"

# --- leaderboard ---
{
  for i in $(seq 1 10000); do
    echo "ZADD leaderboard $((RANDOM % 1000000 + 1)) user:$i"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  leaderboard done"

# --- 500 product tag sets (Set type) ---
{
  TAGS=(electronics fashion sale trending featured clearance new bestseller)
  for i in $(seq 1 500); do
    t1=${TAGS[$((RANDOM % 8))]}
    t2=${TAGS[$((RANDOM % 8))]}
    echo "SADD tags:product:$i $t1 $t2"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  product tags done"

# --- 300 per-user activity feeds (List type) ---
{
  for i in $(seq 1 300); do
    for j in $(seq 1 5); do
      echo "RPUSH activity:$i event:$((RANDOM % 5)):$((RANDOM % 86400))"
    done
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  activity feeds done"

# --- 300 category leaderboards (Sorted Set type) ---
{
  for c in $(seq 1 300); do
    for i in $(seq 1 20); do
      echo "ZADD leaderboard:category:$c $((RANDOM % 100000)) user:$i"
    done
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  category leaderboards done"

# --- 500 orders ---
{
  for i in $(seq 1 500); do
    echo "LPUSH orders:pending order:$i"
    echo "HSET order:$i user_id $((RANDOM % 50000 + 1)) total $((RANDOM % 50000 + 500)) status pending"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  orders done"

# --- stats ---
{
  for path in root products checkout account search cart blog docs; do
    echo "SET stats:pageviews:$path $((RANDOM % 500000 + 10000))"
  done
  echo "SET stats:pageviews $((RANDOM % 5000000 + 100000))"
  echo "SET stats:dau $((RANDOM % 50000 + 5000))"
  echo "SET stats:revenue_today $((RANDOM % 100000 + 10000))"
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  stats done"

# --- big keys ---
# Large string blobs using -x flag to read value from stdin
for i in 0 1 2 3 4; do
  size=$(( (i + 1) * 100000 + 50000 ))
  head -c "$size" /dev/urandom | base64 | tr -d '\n' | head -c "$size" | \
    valkey-cli -c -h valkey-demo -p 6379 -x SET "bigkey:blob:$i" > /dev/null
done
echo "  big string blobs done"

# Large hash (1000 fields with 250-char values)
CHARS="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
{
  for i in $(seq 1 1000); do
    value=$(head -c 200 /dev/urandom | base64 | tr -d '\n' | head -c 250)
    echo "HSET bigkey:cache:lookup field:$i $value"
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  big hash done"

# Game leaderboards (sorted sets ~1.5KB each)
{
  for g in $(seq 0 9); do
    for i in $(seq 1 50); do
      echo "ZADD leaderboard:game:$g $((RANDOM % 1000000 + 1)) player:$i"
    done
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  game leaderboards done"

# --- queue workers (List type) ---
{
  for w in $(seq 0 19); do
    for j in $(seq 1 10); do
      echo "RPUSH queue:worker:$w task:$((RANDOM % 10000)):payload-$((RANDOM % 999))"
    done
  done
} | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
echo "  queue workers done"

# ─── Per-node utilization tiers (Low / Normal / High) ────────────────────────
echo "==> Configuring per-node utilization tiers..."

declare -a SLOT_MIN SLOT_MAX PIP PPORT

idx=0
while IFS=' ' read -r smin smax ip port; do
  SLOT_MIN[$idx]=$smin
  SLOT_MAX[$idx]=$smax
  PIP[$idx]=$ip
  PPORT[$idx]=$port
  idx=$((idx+1))
done < <(valkey-cli -h valkey-demo -p 6379 CLUSTER NODES \
  | awk '/master/ && !/noaddr/ && !/fail/ && !/handshake/ {
      gsub(/@[^ ]*/, "", $2)
      split($2, hp, ":")
      split($9, r, "-")
      printf "%d %d %s %s\n", r[1]+0, r[2]+0, hp[1], hp[2]
    }' \
  | sort -n)

echo "  shard 0 (Low):    ${PIP[0]}:${PPORT[0]}  slots ${SLOT_MIN[0]}-${SLOT_MAX[0]}"
echo "  shard 1 (Normal): ${PIP[1]}:${PPORT[1]}  slots ${SLOT_MIN[1]}-${SLOT_MAX[1]}"
echo "  shard 2 (High):   ${PIP[2]}:${PPORT[2]}  slots ${SLOT_MIN[2]}-${SLOT_MAX[2]}"

# Find a hash tag whose CRC16 slot falls within [min, max]
find_tag() {
  local min=$1 max=$2 n=0 slot
  while true; do
    slot=$(valkey-cli -h valkey-demo -p 6379 CLUSTER KEYSLOT "{t${n}}")
    [ "$slot" -ge "$min" ] && [ "$slot" -le "$max" ] && { printf 't%d' "$n"; return; }
    n=$((n+1))
    [ $n -gt 500 ] && { printf 't%d' "$min"; return; }
  done
}

echo "==> Finding routing tags..."
TAG0=$(find_tag "${SLOT_MIN[0]}" "${SLOT_MAX[0]}")
TAG1=$(find_tag "${SLOT_MIN[1]}" "${SLOT_MAX[1]}")
TAG2=$(find_tag "${SLOT_MIN[2]}" "${SLOT_MAX[2]}")
echo "  {$TAG0} → shard 0 (Low)   {$TAG1} → shard 1 (Normal)   {$TAG2} → shard 2 (High)"

# Pipe N×1KB keys directly to a primary node using RESP protocol
bulk_seed() {
  local ip=$1 port=$2 tag=$3 count=$4
  local VALUE VLEN prefix i pad KEY KLEN
  VALUE=$(printf '%1000s' | tr ' ' 'x')
  VLEN=1000
  prefix="{$tag}:bulk:"
  i=1
  {
    while [ "$i" -le "$count" ]; do
      printf -v pad '%06d' "$i"
      KEY="${prefix}${pad}"
      KLEN=${#KEY}
      printf '*3\r\n$3\r\nSET\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n' \
        "$KLEN" "$KEY" "$VLEN" "$VALUE"
      i=$((i+1))
    done
  } | valkey-cli -h "$ip" -p "$port" --pipe --pipe-timeout 120 > /dev/null
}

echo "==> Bulk seeding nodes (this takes ~30s)..."
bulk_seed "${PIP[0]}" "${PPORT[0]}" "$TAG0" 50000 && echo "  Low node done    (~55 MB)"
bulk_seed "${PIP[1]}" "${PPORT[1]}" "$TAG1" 75000 && echo "  Normal node done (~82 MB)"
bulk_seed "${PIP[2]}" "${PPORT[2]}" "$TAG2" 50000 && echo "  High node done   (~55 MB)"

echo "==> Setting maxmemory per primary..."
valkey-cli -h "${PIP[0]}" -p "${PPORT[0]}" CONFIG SET maxmemory 524288000 > /dev/null  # 500 MB → Low
valkey-cli -h "${PIP[1]}" -p "${PPORT[1]}" CONFIG SET maxmemory 131072000 > /dev/null  # 125 MB → Normal
valkey-cli -h "${PIP[2]}" -p "${PPORT[2]}" CONFIG SET maxmemory 62914560  > /dev/null  #  60 MB → High
echo "  Low=500MB  Normal=100MB  High=60MB"

echo "==> Seed complete."
