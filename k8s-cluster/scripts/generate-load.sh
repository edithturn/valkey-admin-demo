#!/bin/bash
echo "Load generator started."

# Worker A: session churn (50ms) — IDs wrap in a fixed window so the session
# key count stays bounded instead of growing forever and swamping other key types
(
  i=100000
  while true; do
    sid=$(printf '%016x%016x' $((i * 6364136223846793005)) $((RANDOM * 65536 + RANDOM)))
    {
      echo "HSET session:$sid user_id $((RANDOM % 50000 + 1)) role user created_at $(date +%s)"
      echo "EXPIRE session:$sid $((RANDOM % 3600 + 300))"
    } | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    i=$(( (i + 1 - 100000) % 5000 + 100000 ))
    sleep 0.05
  done
) &

# Worker B: product views + leaderboard + pageviews (100ms)
(
  while true; do
    {
      echo "HINCRBY product:$((RANDOM % 500 + 1)) views 1"
      echo "ZINCRBY leaderboard $((RANDOM % 50 + 1)) user:$((RANDOM % 10000 + 1))"
      echo "INCR stats:pageviews"
    } | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    sleep 0.1
  done
) &

# Worker C: order queue (200ms) — order IDs wrap in a fixed window, same reason as Worker A
(
  i=50000
  while true; do
    {
      echo "LPUSH orders:pending order:$i"
      echo "HSET order:$i user_id $((RANDOM % 50000 + 1)) total $((RANDOM % 50000 + 500)) status pending"
      echo "RPOP orders:pending"
    } | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    i=$(( (i + 1 - 50000) % 2000 + 50000 ))
    sleep 0.2
  done
) &

# Worker F: activity feed churn (Lists) — push + trim so keys stay bounded (120ms)
(
  while true; do
    n=$((RANDOM % 300 + 1))
    {
      echo "RPUSH activity:$n event:$((RANDOM % 5)):$((RANDOM % 86400))"
      echo "LTRIM activity:$n -20 -1"
    } | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    sleep 0.12
  done
) &

# Worker G: product tag churn (Sets) (250ms)
(
  TAGS=(electronics fashion sale trending featured clearance new bestseller)
  while true; do
    n=$((RANDOM % 500 + 1))
    t=${TAGS[$((RANDOM % 8))]}
    echo "SADD tags:product:$n $t" | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    sleep 0.25
  done
) &

# Worker H: category leaderboard churn (Sorted Sets) (80ms)
(
  while true; do
    c=$((RANDOM % 300 + 1))
    echo "ZINCRBY leaderboard:category:$c $((RANDOM % 50 + 1)) user:$((RANDOM % 20 + 1))" \
      | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    sleep 0.08
  done
) &

# Worker D: cache churn (150ms)
(
  i=10000
  while true; do
    {
      echo "SET cache:query:$i result-$i EX $((RANDOM % 300 + 30))"
    } | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    i=$((i + 1))
    sleep 0.15
  done
) &

# Worker E: reads (30ms)
(
  while true; do
    {
      echo "HGETALL product:$((RANDOM % 500 + 1))"
      echo "ZRANGE leaderboard 0 9 WITHSCORES"
      echo "GET stats:pageviews"
    } | valkey-cli -c -h valkey-demo -p 6379 > /dev/null
    sleep 0.03
  done
) &

wait
