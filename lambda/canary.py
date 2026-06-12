"""Lambda Canary: ラボの blueprint「Schedule a periodic check of any URL」相当。

環境変数 site の URL を取得し、本文に環境変数 expected の文字列が
含まれなければ例外を送出する（→ AWS/Lambda Errors メトリクスに計上）。
"""
import os
import urllib.request

SITE = os.environ["site"]
EXPECTED = os.environ["expected"]


def handler(event, context):
    req = urllib.request.Request(SITE, headers={"User-Agent": "aws-lambda-canary"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = resp.read().decode("utf-8", errors="replace")

    if EXPECTED not in body:
        raise Exception(f"Validation failed: expected string not found in {SITE}")

    return {"statusCode": 200, "body": "OK"}
