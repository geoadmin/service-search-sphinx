#!/usr/bin/env python3
"""
Read Sphinx log lines from stdin and emit JSON lines compatible with the
json_logger format used in index-sync-rotate.sh.

Usage:
    tail -F /var/log/sphinxsearch/searchd.log | python3 sphinx_log_to_json.py --logger searchd
    tail -F /var/log/sphinxsearch/query.log | python3 sphinx_log_to_json.py --logger query
"""

import argparse
import json
import re
import sys
from datetime import datetime
from datetime import timezone

# searchd.log:  [Mon Mar 30 12:00:00.123 2026] [pid] message
SEARCHD_RE = re.compile(
    r"^\[(?P<day>\w+)\s+(?P<month>\w+)\s+(?P<mday>\d+)\s+(?P<time>[\d:.]+)\s+(?P<year>\d+)\]\s+\[(?P<pid>\d+)\]\s+(?P<message>.+)$"
)

# query.log:  [Mon Mar 30 09:57:14.569 2026] 0.016 sec 0.016 sec [ext/0/ext 0 (0,20)] [index] query text...
QUERY_RE = re.compile(
    r"^\[(?P<day>\w+)\s+(?P<month>\w+)\s+(?P<mday>\d+)\s+(?P<time>[\d:.]+)\s+(?P<year>\d+)\]\s+(?P<duration>[\d.]+)\s+sec\s+(?:[\d.]+\s+sec\s+)?\[(?P<mode>[^\]]*)\]\s+(?P<message>.+)$"
)

MONTHS = {
    "Jan": 1,
    "Feb": 2,
    "Mar": 3,
    "Apr": 4,
    "May": 5,
    "Jun": 6,
    "Jul": 7,
    "Aug": 8,
    "Sep": 9,
    "Oct": 10,
    "Nov": 11,
    "Dec": 12,
}


def parse_sphinx_timestamp(m: re.Match) -> str:
    try:
        month = MONTHS.get(m.group("month"), 1)
        time_parts = m.group("time").split(":")
        h, mi, s_ms = int(time_parts[0]), int(time_parts[1]), time_parts[2]
        s, ms = (s_ms.split(".") + ["000"])[:2]
        dt = datetime(
            int(m.group("year")),
            month,
            int(m.group("mday")),
            h,
            mi,
            int(s),
            int(ms) * 1000,
            tzinfo=timezone.utc,
        )
        return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(ms):03d}Z"
    except (KeyError, ValueError, IndexError, OverflowError):
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def emit(record: dict):
    print(json.dumps(record), flush=True)


def process_stdin(logger: str):
    try:
        for line in sys.stdin:
            line = line.rstrip("\n")
            now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
            record = {
                "Timestamp": now,
                "severity_text": "INFO",
                "log.logger": logger,
                "body.string": line,
            }

            if logger == "searchd":
                m = SEARCHD_RE.match(line)
                if m:
                    record["Timestamp"] = parse_sphinx_timestamp(m)
                    record["process.pid"] = m.group("pid")
                    record["body.string"] = m.group("message")

                    if record["body.string"].startswith("WARNING:"):
                        record["severity_text"] = "WARNING"
                    elif record["body.string"].startswith("ERROR:"):
                        record["severity_text"] = "ERROR"
                    elif record["body.string"].startswith("FATAL:"):
                        record["severity_text"] = "FATAL"

            elif logger == "query":
                m = QUERY_RE.match(line)
                if m:
                    record["Timestamp"] = parse_sphinx_timestamp(m)
                    record["event.category"] = "sphinx"
                    record["event.kind"] = "query"
                    record["event.duration"] = m.group("duration")
                    record["body.string"] = m.group("message")

            emit(record)
    except BrokenPipeError:
        sys.exit(0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--logger", required=True, choices=["searchd", "query"])
    args = parser.parse_args()
    try:
        process_stdin(args.logger)
    except KeyboardInterrupt:
        sys.exit(0)
