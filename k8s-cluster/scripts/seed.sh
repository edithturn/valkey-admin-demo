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

echo "==> Seed complete."
