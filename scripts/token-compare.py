#!/usr/bin/env python3
"""Confronta i token di output delle risposte di Claude Code prima e dopo una data.

Legge i transcript in ~/.claude/projects/*/*.jsonl e conta solo le risposte di
testo (i messaggi dell'assistente senza chiamate a strumenti). Serve a stimare
l'effetto di caveman o di uno stile di output, partendo da quando e' stato attivato.

Uso:
  token-compare.py --since "2026-11-23 18:00"
  token-compare.py --since "2026-11-23 18:00" --days 30 --exclude 95f31490
"""

import argparse
import datetime
import glob
import json
import os
import statistics


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--since", required=True, help='data di attivazione, es. "2026-11-23 18:00"')
    parser.add_argument("--days", type=int, default=14, help="giorni da considerare prima di --since (default 14)")
    parser.add_argument("--exclude", action="append", default=[], help="esclude i transcript il cui percorso contiene questo testo (ripetibile)")
    return parser.parse_args()


def reply_tokens(path):
    """Restituisce (timestamp, output_tokens) per ogni risposta di solo testo."""
    with open(path, errors="ignore") as file:
        for line in file:
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("type") != "assistant":
                continue
            message = entry.get("message") or {}
            tokens = (message.get("usage") or {}).get("output_tokens")
            timestamp = entry.get("timestamp")
            if not tokens or not timestamp:
                continue
            content = message.get("content") or []
            if any(isinstance(part, dict) and part.get("type") == "tool_use" for part in content):
                continue
            moment = datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00")).timestamp()
            yield moment, tokens


def summary(label, values):
    if not values:
        print(f"{label}: nessuna risposta")
        return
    print(f"{label}: risposte={len(values)} media={statistics.mean(values):.0f} mediana={statistics.median(values):.0f}")


def main():
    args = parse_args()
    cut = datetime.datetime.strptime(args.since, "%Y-%m-%d %H:%M").timestamp()
    start = cut - args.days * 86400
    before, after = [], []

    for path in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
        if os.path.getmtime(path) < start or any(text in path for text in args.exclude):
            continue
        for moment, tokens in reply_tokens(path):
            if moment >= cut:
                after.append(tokens)
            elif moment >= start:
                before.append(tokens)

    summary(f"prima ({args.days} giorni)", before)
    summary("dopo", after)
    if len(after) < 100:
        print(f"Attenzione: solo {len(after)} risposte dopo la data, il confronto non e' ancora affidabile.")


if __name__ == "__main__":
    main()
