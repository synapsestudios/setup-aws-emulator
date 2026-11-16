# setup-aws-emulator

GitHub action that installs and starts [AWS Emulator](https://github.com/aws/aws-emulator), a local emulator of the AWS APIs. Later steps in the job call the emulator instead of AWS, with no AWS account.

## Usage

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: synapsestudios/setup-aws-emulator@v1
        with:
          version: 1.0.385

      - run: aws s3 mb s3://my-bucket
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `version` | Emulator version to install, such as `1.0.385`, or `latest`. Versions are listed in [versions.json](https://downloads.aws.com/aws-emulator/packages/aws-emulator/LTS/versions.json). | `latest` |
| `telemetry` | Whether the emulator reports usage data to AWS: `on` or `off`. See [Telemetry in AWS Emulator](https://docs.aws.amazon.com/emulator/latest/userguide/telemetry.html). | `off` |
| `start` | Start the emulator and point later steps at it. Set to `false` to install only. | `true` |

Pin `version` if you want test results to change only when you upgrade. AWS publishes security fixes only in the latest release.

## Outputs

| Name | Description |
|------|-------------|
| `version` | The installed version |
| `endpoint-url` | The URL the emulator serves on, `https://127.0.0.1:9297` |
| `ca-file` | Path of the emulator's certificate |
| `java-truststore-file` | Path of the emulator's trust store for Java |
| `log-file` | Path of the emulator's log |

All but `version` are empty when `start` is `false`.

## What it does

1. Downloads the Debian package for the runner's architecture.
2. Checks the package signature against the AWS publishing key.
3. Installs the package, which puts `aws-emulator` on `PATH`.
4. Sets `EMULATOR_TELEMETRY` for the rest of the job.
5. Starts the emulator in the background on port 9297 and waits for it to be ready.
6. Sets these variables for the rest of the job:

| Variable | Value |
|----------|-------|
| `AWS_ENDPOINT_URL` | `https://127.0.0.1:9297` |
| `AWS_SHARED_CREDENTIALS_FILE` | `~/.aws/emulator/9297/emulator_credentials` |
| `AWS_CONFIG_FILE` | `~/.aws/emulator/9297/config` |
| `AWS_CA_BUNDLE` | `~/.aws/emulator/9297/ca.pem` |
| `AWS_EC2_METADATA_DISABLED` | `true` |
| `AWS_DISABLE_HOST_PREFIX_INJECTION` | `true` |
| `AWS_REGION`, `AWS_DEFAULT_REGION` | `us-east-1` |

Steps 5 and 6 are skipped when `start` is `false`.

## Notes

- **Runners.** Ubuntu and Debian runners, x64 and arm64. AWS publishes no package for macOS or Windows.
- **Real credentials.** Don't set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, or `AWS_PROFILE` in a job that uses the emulator. They take precedence over the emulator's credentials file, and the emulator rejects them.
- **Real AWS in the same job.** After this action runs, the AWS CLI and SDKs in later steps trust only the emulator's certificate and send every request to it. Call AWS from a different job.
- **Node.js, Java, Rust, and .NET.** These SDKs don't read `AWS_CA_BUNDLE`. Set `NODE_EXTRA_CA_CERTS` or `SSL_CERT_FILE` to the `ca-file` output, or point the JVM at `java-truststore-file`. See [Trusting the emulator certificate in each SDK](https://docs.aws.amazon.com/emulator/latest/userguide/point-sdk-to-emulator.html#point-sdk-ca).
- **State.** The emulator keeps resources in memory. They're gone when the job ends.

## Install only

Use `start: false` when your own script starts the emulator, for example to choose a port or run more than one.

```yaml
- uses: synapsestudios/setup-aws-emulator@v1
  with:
    version: 1.0.385
    start: false

- run: tests/emulator/run.sh
```
