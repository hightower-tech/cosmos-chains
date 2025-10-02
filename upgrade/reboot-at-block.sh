#!/usr/bin/env bash
set -euo pipefail

# ========== CONFIG ==========
RPC_URL="${RPC_URL:-http://127.0.0.1:26657}"   # Tendermint/Cosmos RPC
TARGET_HEIGHT="${TARGET_HEIGHT:-1657000}"      # target block height
SERVICE_NAME="${SERVICE_NAME:-lumera-validator}"  # systemd service to restart
POLL_INTERVAL="${POLL_INTERVAL:-5}"            # seconds between polls
MAX_BLOCK=$((TARGET_HEIGHT + 5))
# ============================

# check dependencies
for cmd in curl jq systemctl date bc; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "Error: $cmd is not installed." >&2
    exit 2
  fi
done

echo "$(date -Is) watch-block-and-restart started: RPC=${RPC_URL}, target=${TARGET_HEIGHT}, service=${SERVICE_NAME}"

prev_block=0
prev_time=0

while true; do
  # get latest block height and timestamp
  latest_block=$(curl -s "${RPC_URL%/}/status" | jq -r '.result.sync_info.latest_block_height')
  latest_time=$(curl -s "${RPC_URL%/}/block?height=${latest_block}" | jq -r '.result.block.header.time')

  if [[ -z "$latest_block" || "$latest_block" == "null" || -z "$latest_time" || "$latest_time" == "null" ]]; then
    echo "$(date -Is) Could not get latest block or timestamp. Waiting ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
    continue
  fi

  # convert ISO 8601 to epoch seconds
  latest_sec=$(date -d "$latest_time" +%s)

  echo "$(date -Is) Current block: $latest_block"

  if (( prev_block > 0 )); then
    # calculate block interval using previous measurement
    blocks_passed=$((latest_block - prev_block))
    time_passed=$((latest_sec - prev_time))

    if (( blocks_passed > 0 )); then
      block_interval=$(echo "$time_passed / $blocks_passed" | bc -l)
      remaining_blocks=$((TARGET_HEIGHT - latest_block))
      if (( remaining_blocks > 0 )); then
        remaining_seconds=$(echo "$remaining_blocks * $block_interval" | bc -l)
        hours=$(echo "$remaining_seconds/3600" | bc)
        minutes=$(echo "($remaining_seconds%3600)/60" | bc)
        seconds=$(echo "$remaining_seconds%60" | bc)
        echo "Estimated remaining time until block ${TARGET_HEIGHT}: ${hours}h ${minutes}m ${seconds}s"
      else
        echo "Target block already reached or passed."
      fi
    else
      echo "No new blocks since last check."
    fi
  fi

  # restart logic with +5 block tolerance
  if (( latest_block >= TARGET_HEIGHT && latest_block <= MAX_BLOCK )); then
    echo "$(date -Is) Target block (${TARGET_HEIGHT}) reached. Restarting service ${SERVICE_NAME}..."
    if systemctl restart "${SERVICE_NAME}"; then
      echo "$(date -Is) Service ${SERVICE_NAME} successfully restarted."
      exit 0
    else
      echo "$(date -Is) Failed to restart ${SERVICE_NAME}." >&2
      sleep "$POLL_INTERVAL"
    fi
  else
    if (( latest_block > MAX_BLOCK )); then
      echo "$(date -Is) Block ${latest_block} is higher than allowed (${MAX_BLOCK}), skipping restart."
      exit 0
    fi
  fi

  # save current as previous for next iteration
  prev_block=$latest_block
  prev_time=$latest_sec

  sleep "$POLL_INTERVAL"
done
