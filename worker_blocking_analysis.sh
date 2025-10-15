#!/usr/bin/env bash
# Simple and reliable worker blocking time analysis using time + strace
# Usage: ./worker_blocking_analysis.sh <command...>
# Example: ./worker_blocking_analysis.sh ruby sync-test.rb

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <command...>" >&2
  echo "Example: $0 ruby sync-test.rb" >&2
  exit 1
fi

CMD=("$@")
OUT_PREFIX="blocking_analysis_$(date +%Y%m%d_%H%M%S)"
TIME_OUT="${OUT_PREFIX}_time.txt"
STRACE_OUT="${OUT_PREFIX}_strace.txt"
SUMMARY="${OUT_PREFIX}_summary.txt"

echo "=========================================="
echo "Worker Blocking Time Analysis"
echo "=========================================="
echo "Command: ${CMD[*]}"
echo "=========================================="
echo ""

# Run with time to get overall metrics
echo "Running command with time measurement..."
/usr/bin/time -v "${CMD[@]}" 2>&1 | tee "$TIME_OUT"

echo ""
echo "Running command with strace to analyze syscalls..."
# Run with strace to see where time is spent
strace -c -f -w "${CMD[@]}" 2>&1 | tee "$STRACE_OUT"

echo ""
echo "=========================================="
echo "Analysis Summary"
echo "=========================================="

{
  echo "Worker Blocking Time Analysis"
  echo "=============================="
  echo "Command: ${CMD[*]}"
  echo "Timestamp: $(date)"
  echo ""

  # Extract metrics from time output
  echo "Overall Timing (from /usr/bin/time):"
  echo "------------------------------------"

  ELAPSED=$(grep "Elapsed (wall clock) time" "$TIME_OUT" | sed 's/.*: //' || echo "N/A")
  USER=$(grep "User time (seconds):" "$TIME_OUT" | sed 's/.*: //' || echo "0")
  SYS=$(grep "System time (seconds):" "$TIME_OUT" | sed 's/.*: //' || echo "0")
  CPU_PCT=$(grep "Percent of CPU this job got:" "$TIME_OUT" | sed 's/.*: //' | sed 's/%//' || echo "0")
  VOL_CTXT=$(grep "Voluntary context switches:" "$TIME_OUT" | sed 's/.*: //' || echo "0")
  INVOL_CTXT=$(grep "Involuntary context switches:" "$TIME_OUT" | sed 's/.*: //' || echo "0")

  echo "Elapsed (wall) time: $ELAPSED"
  echo "User time: ${USER}s"
  echo "System time: ${SYS}s"

  # Calculate CPU time
  CPU_TIME=$(awk -v u="$USER" -v s="$SYS" 'BEGIN {printf "%.3f", u+s}')
  echo "Total CPU time: ${CPU_TIME}s"
  echo "CPU usage: ${CPU_PCT}%"

  # Convert elapsed to seconds for calculation
  if [[ "$ELAPSED" =~ ([0-9]+):([0-9]+\.[0-9]+) ]]; then
    MIN="${BASH_REMATCH[1]}"
    SEC="${BASH_REMATCH[2]}"
    ELAPSED_SEC=$(awk -v m="$MIN" -v s="$SEC" 'BEGIN {printf "%.3f", m*60+s}')
  elif [[ "$ELAPSED" =~ ([0-9]+):([0-9]+):([0-9]+\.[0-9]+) ]]; then
    HOUR="${BASH_REMATCH[1]}"
    MIN="${BASH_REMATCH[2]}"
    SEC="${BASH_REMATCH[3]}"
    ELAPSED_SEC=$(awk -v h="$HOUR" -v m="$MIN" -v s="$SEC" 'BEGIN {printf "%.3f", h*3600+m*60+s}')
  else
    ELAPSED_SEC="$ELAPSED"
  fi

  # Calculate blocking time
  BLOCKING_TIME=$(awk -v e="$ELAPSED_SEC" -v c="$CPU_TIME" 'BEGIN {b=e-c; if(b<0) b=0; printf "%.3f", b}')
  BLOCKING_PCT=$(awk -v b="$BLOCKING_TIME" -v e="$ELAPSED_SEC" 'BEGIN {if(e>0) printf "%.2f", (b/e)*100; else print "0"}')
  CPU_ACTIVE_PCT=$(awk -v c="$CPU_TIME" -v e="$ELAPSED_SEC" 'BEGIN {if(e>0) printf "%.2f", (c/e)*100; else print "0"}')

  echo ""
  echo "Blocking Analysis:"
  echo "------------------"
  echo "Total blocking time: ${BLOCKING_TIME}s"
  echo "Blocking percentage: ${BLOCKING_PCT}%"
  echo "CPU active percentage: ${CPU_ACTIVE_PCT}%"
  echo ""

  echo "Context Switches:"
  echo "-----------------"
  echo "Voluntary: $VOL_CTXT (process yielding, typically waiting for I/O)"
  echo "Involuntary: $INVOL_CTXT (preempted by scheduler)"
  echo ""

  # Parse strace output for syscall breakdown
  echo "System Call Time Breakdown (from strace):"
  echo "------------------------------------------"

  # Extract the summary table from strace
  if grep -q "% time" "$STRACE_OUT"; then
    # Get network-related syscalls
    echo ""
    echo "Network I/O syscalls:"
    grep -E "^\s*[0-9.]+" "$STRACE_OUT" | grep -E "(recvfrom|sendto|recv|send|connect|poll|select|epoll)" || echo "  (none detected)"

    echo ""
    echo "Top syscalls by time:"
    grep -E "^\s*[0-9.]+" "$STRACE_OUT" | head -10 || echo "  (no data)"

    echo ""
    echo "Summary line:"
    grep "^[0-9.]*\s*[0-9.]*\s*[0-9]*\s*total$" "$STRACE_OUT" || echo "  (no data)"
  fi

  echo ""
  echo "Interpretation:"
  echo "---------------"

  if (( $(awk -v b="$BLOCKING_PCT" 'BEGIN {print (b>90)}') )); then
    echo "⚠️  HEAVILY I/O BOUND (${BLOCKING_PCT}% blocked)"
    echo ""
    echo "The worker spends ${BLOCKING_PCT}% of its time blocked waiting for I/O."
    echo "Only ${CPU_ACTIVE_PCT}% of time is spent actively processing."
    echo ""
    echo "Current worker utilization: ${CPU_ACTIVE_PCT}%"

    POTENTIAL_GAIN=$(awk -v cpu="$CPU_ACTIVE_PCT" 'BEGIN {if(cpu>0) printf "%.1f", 100.0/cpu; else print "N/A"}')
    echo "Potential throughput gain if waits eliminated: ${POTENTIAL_GAIN}x"
    echo ""
    echo "Recommendations:"
    echo "  • Use async I/O or streaming to reduce blocking"
    echo "  • Consider connection pooling / HTTP keep-alive"
    echo "  • Make parallel/concurrent requests where possible"
    echo "  • A single worker can only process work ${CPU_ACTIVE_PCT}% of the time"
  elif (( $(awk -v b="$BLOCKING_PCT" 'BEGIN {print (b>50)}') )); then
    echo "⚠️  MODERATELY I/O BOUND (${BLOCKING_PCT}% blocked)"
    echo ""
    echo "The worker spends ${BLOCKING_PCT}% blocked and ${CPU_ACTIVE_PCT}% active."
    echo "There's room for optimization but it's not critically blocked."
  else
    echo "✓  CPU BOUND OR WELL BALANCED (${BLOCKING_PCT}% blocked)"
    echo ""
    echo "Worker utilization is good: ${CPU_ACTIVE_PCT}% active processing."
  fi

  echo ""
  echo "Data files:"
  echo "-----------"
  echo "Time output: $TIME_OUT"
  echo "Strace output: $STRACE_OUT"
  echo "This summary: $SUMMARY"

} | tee "$SUMMARY"

echo ""
echo "=========================================="
