#!/bin/zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  print -u2 'usage: extract_direct_session_corpus.sh <session.jsonl> <output-directory>'
  exit 64
fi

session_path=$1
output_directory=$2

[[ -f $session_path ]]
mkdir -p $output_directory

messages_path="$output_directory/direct-session-messages.jsonl"
tool_calls_path="$output_directory/direct-session-tool-calls.jsonl"
tool_outputs_path="$output_directory/direct-session-tool-output-metadata.jsonl"
plans_path="$output_directory/direct-session-plans.jsonl"
timeline_path="$output_directory/direct-session-timeline.jsonl"
summary_path="$output_directory/direct-session-summary.json"

jq -c '
  select(.type == "response_item" and .payload.type == "message")
  | select(.payload.role == "user" or .payload.role == "assistant")
  | {
      timestamp,
      kind: "message",
      role: .payload.role,
      text: ([.payload.content[]? | .text // .input_text // .output_text // ""] | join(" "))
    }
' "$session_path" > "$messages_path"

jq -c '
  select(.type == "response_item" and .payload.type == "function_call")
  | .payload.arguments as $arguments
  | {
      timestamp,
      kind: "tool_call",
      name: .payload.name,
      callID: .payload.call_id,
      arguments: (try ($arguments | fromjson) catch $arguments)
    }
' "$session_path" > "$tool_calls_path"

jq -c '
  select(.type == "response_item" and .payload.type == "function_call_output")
  | (.payload.output | tostring) as $output
  | {
      timestamp,
      kind: "tool_output_metadata",
      callID: .payload.call_id,
      outputBytes: ($output | utf8bytelength),
      outputCharacters: ($output | length),
      outputPrefix: $output[0:400],
      outputSuffix: (if ($output | length) > 400 then $output[-400:] else $output end)
    }
' "$session_path" > "$tool_outputs_path"

jq -c '
  select(.type == "response_item" and .payload.type == "function_call" and .payload.name == "update_plan")
  | .payload.arguments as $arguments
  | {
      timestamp,
      kind: "plan_update",
      callID: .payload.call_id,
      plan: (try ($arguments | fromjson) catch {unparsed: $arguments})
    }
' "$session_path" > "$plans_path"

jq -cs 'sort_by(.timestamp)[]' \
  "$messages_path" \
  "$tool_calls_path" \
  "$tool_outputs_path" > "$timeline_path"

jq -s \
  --arg sessionPath $session_path \
  --arg sessionSHA256 "$(shasum -a 256 "$session_path" | awk '{print $1}')" \
  --arg timelineSHA256 "$(shasum -a 256 "$timeline_path" | awk '{print $1}')" \
  --arg plansSHA256 "$(shasum -a 256 "$plans_path" | awk '{print $1}')" \
  '
  {
    schemaVersion: 1,
    source: {
      path: $sessionPath,
      sha256: $sessionSHA256,
      bytes: (input_filename | 0)
    },
    firstTimestamp: (map(.timestamp) | min),
    lastTimestamp: (map(.timestamp) | max),
    counts: {
      records: length,
      messages: ([.[] | select(.type == "response_item" and .payload.type == "message" and (.payload.role == "user" or .payload.role == "assistant"))] | length),
      userMessages: ([.[] | select(.type == "response_item" and .payload.type == "message" and .payload.role == "user")] | length),
      assistantMessages: ([.[] | select(.type == "response_item" and .payload.type == "message" and .payload.role == "assistant")] | length),
      toolCalls: ([.[] | select(.type == "response_item" and .payload.type == "function_call")] | length),
      toolOutputs: ([.[] | select(.type == "response_item" and .payload.type == "function_call_output")] | length),
      planUpdates: ([.[] | select(.type == "response_item" and .payload.type == "function_call" and .payload.name == "update_plan")] | length)
    },
    artifacts: {
      timeline: {path: "direct-session-timeline.jsonl", sha256: $timelineSHA256},
      plans: {path: "direct-session-plans.jsonl", sha256: $plansSHA256}
    },
    contentBoundary: "Raw reasoning records are intentionally excluded. Full tool outputs remain in the immutable hashed source; the derived corpus stores bounded prefixes, suffixes, and sizes for navigation."
  }
  ' "$session_path" > "$summary_path"

# Replace the placeholder source size without loading the 132 MB file a second time.
source_bytes=$(stat -f '%z' "$session_path")
summary_tmp="$summary_path.tmp"
jq --argjson sourceBytes "$source_bytes" '.source.bytes = $sourceBytes' "$summary_path" > "$summary_tmp"
mv "$summary_tmp" "$summary_path"

jq -e '.' "$summary_path" >/dev/null
print -- $timeline_path
print -- $plans_path
print -- $summary_path
