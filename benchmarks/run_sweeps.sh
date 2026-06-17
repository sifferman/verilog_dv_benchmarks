#!/usr/bin/env bash
# Run the four sweep configurations and produce one CSV per sweep, ready to
# attach to a GitHub release.
#
# Configurations (matrix of model × MCP):
#   claudecode_sonnet4.6.csv                       — Sonnet 4.6, no MCP
#   claudecode_opus4.7-1M.csv                      — Opus 4.7 with 1M context, no MCP
#   claudecode_sonnet4.6_SeanMcLoughlinMcpVcd.csv  — Sonnet + mcp-vcd
#   claudecode_opus4.7-1M_SeanMcLoughlinMcpVcd.csv — Opus 1M + mcp-vcd
#
# Each sweep runs every problem in problems/ with:
#   workers=24, max-budget=$2/problem, wall-clock=10min/problem.
# With ~10 min/problem on 24 workers, all 95 problems finish in ~40 min/sweep.
#
# Usage:
#   bash benchmarks/run_sweeps.sh                # all four
#   bash benchmarks/run_sweeps.sh sonnet         # just the sonnet (no-MCP) sweep
#   bash benchmarks/run_sweeps.sh sonnet_mcp     # just the sonnet + mcp sweep
#   bash benchmarks/run_sweeps.sh opus           # just the opus 1M (no-MCP) sweep
#   bash benchmarks/run_sweeps.sh opus_mcp       # just the opus 1M + mcp sweep
set -euo pipefail

cd "$(dirname "$0")/.."

WORKERS=24
MAX_BUDGET_USD=2.00
TIMEOUT_SECONDS=600

OUTPUT_DIR="benchmarks/runs"
mkdir -p "$OUTPUT_DIR"

run_sweep() {
    local sweep_name="$1"
    local model_alias="$2"
    local extra_flags="$3"

    local csv_path="$OUTPUT_DIR/claudecode_${sweep_name}.csv"
    local log_path="$OUTPUT_DIR/claudecode_${sweep_name}.log"

    echo ""
    echo "============================================================"
    echo "  Sweep: $sweep_name"
    echo "  Model: $model_alias"
    echo "  CSV  : $csv_path"
    echo "  Log  : $log_path"
    echo "  Extra: $extra_flags"
    echo "============================================================"

    python3 python/run_claude_code_agent.py \
        --all \
        --model "$model_alias" \
        --workers "$WORKERS" \
        --max-budget-usd "$MAX_BUDGET_USD" \
        --timeout-seconds "$TIMEOUT_SECONDS" \
        --csv-out "$csv_path" \
        --resume \
        $extra_flags \
        2>&1 | tee "$log_path"
}

run_sonnet()       { run_sweep "sonnet4.6"                         "claude-sonnet-4-6"   ""; }
run_opus()         { run_sweep "opus4.7-1M"                        "claude-opus-4-7[1m]" ""; }
run_sonnet_mcp()   { run_sweep "sonnet4.6_SeanMcLoughlinMcpVcd"    "claude-sonnet-4-6"   "--mcp-config benchmarks/mcp-vcd.json --enable-vcd-dump"; }
run_opus_mcp()     { run_sweep "opus4.7-1M_SeanMcLoughlinMcpVcd"   "claude-opus-4-7[1m]" "--mcp-config benchmarks/mcp-vcd.json --enable-vcd-dump"; }

case "${1:-all}" in
    sonnet)      run_sonnet       ;;
    opus)        run_opus         ;;
    sonnet_mcp)  run_sonnet_mcp   ;;
    opus_mcp)    run_opus_mcp     ;;
    all)
        run_sonnet
        run_opus
        run_sonnet_mcp
        run_opus_mcp
        ;;
    *)
        echo "Unknown sweep: $1" >&2
        echo "Valid: sonnet, opus, sonnet_mcp, opus_mcp, all" >&2
        exit 1
        ;;
esac

echo ""
echo "All requested sweeps complete. CSVs:"
ls -la "$OUTPUT_DIR"/claudecode_*.csv 2>/dev/null
