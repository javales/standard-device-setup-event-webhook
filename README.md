# standard-device-setup-event-webhook

## SDS - Submit - Failure Report

Reports an install download failure event to a Zapier webhook as a structured JSON payload. Runs as part of the Standard Device Setup (SDS) workflow when the primary installer download source is unavailable.

### Workflow

```mermaid
flowchart TD
    START([Script Start]) --> LOG_START[Log start timestamp]
    LOG_START --> VAL_BIN[validateBinaryFiles\nVerify all required binaries exist\nand are executable]

    VAL_BIN -->|Missing or non-executable binary| ERR_BIN[Log error]
    ERR_BIN --> EXIT_ERR([exitScript / exit 1])

    VAL_BIN -->|All binaries valid| VAL_SN[validateSerialNumber\nCapture serial via system_profiler]

    VAL_SN -->|Serial number empty| ERR_SN[Log error]
    ERR_SN --> EXIT_ERR

    VAL_SN -->|Serial number captured| BUILD[buildInstallerDownloadFailurePayload\nConstruct JSON via jq\nevent_type · event_id · timestamp\nserial_number · error code 404\nsource/process/team metadata]

    BUILD --> VAL_PAY[validatePayload\nParse payload with jq to confirm\nwell-formed JSON]

    VAL_PAY -->|jq parse fails| ERR_PAY[Log error + raw payload]
    ERR_PAY --> EXIT_ERR

    VAL_PAY -->|jq parse succeeds| SEND[sendStatus\nPOST payload to Zapier webhook\nvia curl]

    SEND -->|curl exit code ≠ 0| ERR_CURL[Log exception]
    ERR_CURL --> CLEANUP_ERR[curlTempCleanup]
    CLEANUP_ERR --> EXIT_ERR

    SEND -->|curl exit code = 0| HTTP{HTTP response code}

    HTTP -->|≠ 200| ERR_HTTP[Log exception]
    ERR_HTTP --> CLEANUP_HTTP[curlTempCleanup]
    CLEANUP_HTTP --> EXIT_ERR

    HTTP -->|200 OK| SUCCESS[Log success]
    SUCCESS --> CLEANUP_OK[curlTempCleanup]
    CLEANUP_OK --> LOG_END[Log end timestamp]
    LOG_END --> EXIT_OK([exit 0])

    TRAP([SIGTERM / SIGINT]) -.->|trap| TRAP_CLEAN[curlTempCleanup]
    TRAP_CLEAN -.-> TRAP_LOG[earlyExitLogging]
    TRAP_LOG -.-> EXIT_TRAP([exit 130])
```

### JSON Payload Structure

```json
{
  "event_type": "com.company.standard.installer.download-failure",
  "event_id": "<uuid>",
  "timestamp": "<ISO-8601-UTC>",
  "summary": "Installer Download Failed",
  "description": "*Standard Device Setup* - resorted to FALLBACK download source",
  "data": {
    "source_system": "sample-installer",
    "impact": {
      "process": "Sample Installer Download",
      "environment": "production",
      "managing_team": "Systems Engineers"
    },
    "device": {
      "serial_number": "<device-serial>"
    },
    "error": {
      "code": 404,
      "message": "failed to download from PRIMARY download source: ..."
    }
  }
}
```