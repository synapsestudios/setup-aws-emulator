#!/usr/bin/env bash
# Starts AWS Emulator in the background, waits until it is ready, and points
# the AWS CLI and SDKs in later steps at it.
#
# Inputs, from the environment:
#   EMULATOR_TELEMETRY  on or off
set -euo pipefail

log="${RUNNER_TEMP:-/tmp}/aws-emulator.log"

nohup aws-emulator --telemetry "${EMULATOR_TELEMETRY:-off}" >"$log" 2>&1 &
pid=$!

# The emulator logs JSON lines. The startup line is the documented way to
# find its endpoint and files. Its values sit under "fields".
info=""
for _ in $(seq 120); do
  info=$(jq -Rc 'fromjson? | (.fields? // .) | select(.message? == "emulator server information")' "$log" | head -n 1)
  [ -n "$info" ] && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.5
done

if [ -z "$info" ]; then
  echo "::error::AWS Emulator did not start"
  cat "$log"
  exit 1
fi

field() { jq -r --arg name "$1" '.[$name] // empty' <<<"$info"; }
endpoint_url=$(field endpoint_url)
health_check_url=$(field health_check_url)
config_file=$(field config_file)
ca_file=$(field ca_file)
java_truststore_file=$(field java_truststore_file)

curl -sf --retry 10 --retry-delay 1 --retry-connrefused --cacert "$ca_file" "$health_check_url" >/dev/null
echo "AWS Emulator is ready at $endpoint_url"

{
  echo "AWS_ENDPOINT_URL=$endpoint_url"
  echo "AWS_SHARED_CREDENTIALS_FILE=$(dirname "$config_file")/emulator_credentials"
  echo "AWS_CONFIG_FILE=$config_file"
  echo "AWS_CA_BUNDLE=$ca_file"
  echo "AWS_EC2_METADATA_DISABLED=true"
  echo "AWS_DISABLE_HOST_PREFIX_INJECTION=true"
  echo "AWS_REGION=us-east-1"
  echo "AWS_DEFAULT_REGION=us-east-1"
} >>"$GITHUB_ENV"

{
  echo "endpoint-url=$endpoint_url"
  echo "ca-file=$ca_file"
  echo "java-truststore-file=$java_truststore_file"
  echo "log-file=$log"
} >>"$GITHUB_OUTPUT"
