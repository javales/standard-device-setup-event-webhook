#!/bin/bash
# Standard Device Setup - Log status to webhook endpoint
# Version: 0.1
#
# Description:
# - Send Endpoint Resource Status Reporting event data as json payload to webhook
#
# Change History:
# 04/29/2026 - j.vales - Created

# BINARY VARIABLES
AWK_BINARY="/usr/bin/awk"
BASENAME_BINARY="/usr/bin/basename"
CAT_BINARY="/bin/cat"
CURL_BINARY="/usr/bin/curl"
DATE_BINARY="/bin/date"
ECHO_BINARY="/bin/echo"
GREP_BINARY="/usr/bin/grep"
HEAD_BINARY="/usr/bin/head"
JQ_BINARY="/usr/bin/jq"
MKTEMP_BINARY="/usr/bin/mktemp"
RM_BINARY="/bin/rm"
SYSTEM_PROFILER_BINARY="/usr/sbin/system_profiler"
TEE_BINARY="/usr/bin/tee"
TR_BINARY="/usr/bin/tr"
UUIDGEN_BINARY="/usr/bin/uuidgen"
BINARY_FILE_LIST=("$AWK_BINARY" "$BASENAME_BINARY" "$CAT_BINARY" "$CURL_BINARY" "$DATE_BINARY" "$ECHO_BINARY" "$GREP_BINARY" "$HEAD_BINARY" "$JQ_BINARY" "$MKTEMP_BINARY" "$SYSTEM_PROFILER_BINARY" "$TEE_BINARY" "$TR_BINARY" "$UUIDGEN_BINARY")

# GLOBAL VARIABLES
#CURL_TMP_PROCESS_FILE=/tmp/sds_curl_out.$$
CURL_TMP_PROCESS_FILE=$("$MKTEMP_BINARY") # Recommended "modern" method
SDS_REPORT_LOG="/Library/Logs/StandardDeviceSetup/Standard-DeviceSetup.log"
ENDPOINT_URL="https://hooks.zapier.com/hooks/catch/0000000/xxxxxxx/"
SCRIPT_NAME=$($BASENAME_BINARY "$0")

SERIAL_NUMBER=$($SYSTEM_PROFILER_BINARY SPHardwareDataType 2>/dev/null | $GREP_BINARY -i "serial number" | /usr/bin/awk '{print $4}')

earlyExitLogging () { # No use of functions, since conditionally called as trap function
    "$ECHO_BINARY" "WARNING: Early script termination detected" | "$TEE_BINARY" -a "$SDS_REPORT_LOG"
    SCRIPT_TIME_END=$("$DATE_BINARY" "+%Y-%m-%d-%H-%M-%S")
    "$ECHO_BINARY" "Script (${SCRIPT_NAME}) END: ${SCRIPT_TIME_END}" | "$TEE_BINARY" -a "$SDS_REPORT_LOG"
}

curlTempCleanup () { # No use of functions, since conditionally called as trap function
    "$ECHO_BINARY" "Cleaning up temp curl output file, if found..." >> "$SDS_REPORT_LOG"
    if [ -f "$CURL_TMP_PROCESS_FILE" ]; then
        "$RM_BINARY" -f "$CURL_TMP_PROCESS_FILE"
        "$ECHO_BINARY" "Deleted temp curl output file: ${CURL_TMP_PROCESS_FILE}" >> "$SDS_REPORT_LOG"
    fi
}

exitScript () {
    SCRIPT_TIME_END=$("$DATE_BINARY" "+%Y-%m-%d-%H-%M-%S")
    sLogEcho "Script (${SCRIPT_NAME}) END: ${SCRIPT_TIME_END}"
    exit 1
}

sLog () {
    local LOGGING_MESSAGE
    LOGGING_MESSAGE=$1
    if [[ -n "$LOGGING_MESSAGE" ]]; then
        "$ECHO_BINARY" "$LOGGING_MESSAGE" >> "$SDS_REPORT_LOG"
    else
        "$ECHO_BINARY" "$("$DATE_BINARY" "+%Y-%m-%d-%H-%M-%S") ERROR: ${FUNCNAME[0]} requires a string to be passed as an argument as the logging message; exiting script" | "$TEE_BINARY" -a "$SDS_REPORT_LOG"
        exitScript
    fi
}

sLogEcho () {
    local LOGGING_MESSAGE
    LOGGING_MESSAGE=$1
    if [[ -n "$LOGGING_MESSAGE" ]]; then
        "$ECHO_BINARY" "$LOGGING_MESSAGE" | "$TEE_BINARY" -a "$SDS_REPORT_LOG"
    else
        "$ECHO_BINARY" "$("$DATE_BINARY" "+%Y-%m-%d-%H-%M-%S") ERROR: ${FUNCNAME[0]} requires a string to be passed as an argument as the logging message; exiting script" | "$TEE_BINARY" -a "$SDS_REPORT_LOG"
        exitScript
    fi
}

validateBinaryFiles () {
    for BINARY_FILE in "${BINARY_FILE_LIST[@]}"; do
        if [ ! -x "$BINARY_FILE" ]; then
            sLogEcho "Failed validation of binary file ${BINARY_FILE}; ${FUNCNAME[0]} exiting script..."
            exitScript
        fi
    done
    sLog "Validation Successful (function: ${FUNCNAME[0]})"
}

validateSerialNumber () {
    if [ -z "$SERIAL_NUMBER" ]; then
        sLogEcho "Failed to capture serial number; ${FUNCNAME[0]} exiting script..."
        exitScript
    fi
    sLog "Validation Successful (function: ${FUNCNAME[0]})"
}

buildSDRDownloadFailurePayload () { # Baseline payload based on the Jamf Setup Manager webhook payload
    EVENT_TYPE="com.standard.uit-comm.sdr-installer.download-failure"
    EVENT_ID=$("$UUIDGEN_BINARY" | "$TR_BINARY" '[:upper:]' '[:lower:]')
    EVENT_TIMESTAMP=$("$DATE_BINARY" -u +"%Y-%m-%dT%H:%M:%SZ")
    EVENT_SUMMARY="SDR Download Failed"
    EVENT_DESCRIPTION="*Standard Device Setup* - resorted to FALLBACK download source"
    EVENT_ERROR_CODE=404
    EVENT_ERROR_MESSAGE="failed to download from PRIMARY download source: https://example.com/installers/sdr/mac/autoupdater/current/enrollment/SDR%20-%20Enrollment%20Only.dmg)"
    EVENT_SOURCE_SYSTEM="sdr-installer"
    EVENT_PROCESS="Jamf SDS SDR Download"
    EVENT_ENVIRONMENT="production"
    EVENT_MANAGING_TEAM="EED Systems Engineers"

    CURL_PAYLOAD=$("$JQ_BINARY" -n \
        --arg e_type "$EVENT_TYPE" \
        --arg e_id "$EVENT_ID" \
        --arg e_timestamp "$EVENT_TIMESTAMP" \
        --arg e_summary "$EVENT_SUMMARY" \
        --arg e_description "$EVENT_DESCRIPTION" \
        --argjson e_error_code $EVENT_ERROR_CODE \
        --arg e_error_message "$EVENT_ERROR_MESSAGE" \
        --arg e_serial_number "$SERIAL_NUMBER" \
        --arg e_source_system "$EVENT_SOURCE_SYSTEM" \
        --arg e_process "$EVENT_PROCESS" \
        --arg e_environment "$EVENT_ENVIRONMENT" \
        --arg e_managing_team "$EVENT_MANAGING_TEAM" \
        '{
            "event_type": $e_type,
            "event_id": $e_id,
            "timestamp": $e_timestamp,
            "summary": $e_summary,
            "description": $e_description,
            "data": {
                "source_system": $e_source_system,
                "impact": {
                    "process": $e_process,
                    "environment": $e_environment,
                    "managing_team": $e_managing_team
                },
                "device": {
                    "serial_number": $e_serial_number
                },
                "error": {
                    "code": $e_error_code,
                    "message": $e_error_message
                }
            }
        }'
    )
}

validatePayload () {
    "$ECHO_BINARY" "$CURL_PAYLOAD" | "$JQ_BINARY" . >> "$SDS_REPORT_LOG"
    JQ_EXIT_CODE=$?
    if [ "$JQ_EXIT_CODE" -eq 0 ]; then
        sLogEcho "Validation Successful (function: ${FUNCNAME[0]})"
    else
        sLogEcho "Failed to validate below payload json format (exit code: ${JQ_EXIT_CODE}); ${FUNCNAME[0]} exiting script..."
        sLogEcho "$CURL_PAYLOAD"
        exitScript
    fi
}

sendStatus () {
    HTTP_RESPONSE=$("$CURL_BINARY" -s -w "%{http_code}" -o "$CURL_TMP_PROCESS_FILE" \
        -X POST "$ENDPOINT_URL" \
        -H "Content-Type: application/json" \
        -d "$CURL_PAYLOAD")
    CURL_STATUS_CODE=$?
    if [ "$CURL_STATUS_CODE" -ne 0 ]; then
        sLogEcho "EXCEPTION: Curl command status code ${CURL_STATUS_CODE} indicates a problem occurred; ${FUNCNAME[0]} exiting script..."
        curlTempCleanup
        exitScript
    else
        sLog "Curl command status code: ${CURL_STATUS_CODE}"
    fi
    if [ "$HTTP_RESPONSE" -ne 200 ]; then
        sLogEcho "EXCEPTION: Webhook HTTP response ${HTTP_RESPONSE} unexpected; ${FUNCNAME[0]} exiting script..."
        curlTempCleanup
        exitScript
    else
        sLog "Webhook HTTP Response: ${HTTP_RESPONSE}"
    fi
    sLogEcho "Status submission to webhook successful"
    curlTempCleanup
}

trap 'curlTempCleanup; earlyExitLogging; exit 130' SIGTERM TERM SIGINT # Logging of early script termination and curl temp file cleanup

SCRIPT_TIME_START=$($DATE_BINARY "+%Y-%m-%d-%H-%M-%S")
sLogEcho "Script (${SCRIPT_NAME}) START: ${SCRIPT_TIME_START}"
validateBinaryFiles
validateSerialNumber
buildSDRDownloadFailurePayload
validatePayload
sendStatus
SCRIPT_TIME_END=$("$DATE_BINARY" "+%Y-%m-%d-%H-%M-%S")
sLogEcho "Script (${SCRIPT_NAME}) END: ${SCRIPT_TIME_END}"
exit 0
