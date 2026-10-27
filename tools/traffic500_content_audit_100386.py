#!/usr/bin/env python3
"""Export auditable evidence for DEDA's 500-question Arabic road-safety bank.

This is a STRUCTURAL CONTENT AUDIT, not legal validation or official Iraq
Highway Code verification. Missing citations and unreviewed distractors make
the full bank UNSUITABLE FOR PUBLIC RELEASE until expert review completes.

Writes a UTF-8-SIG CSV for Arabic spreadsheets and a machine-readable JSON
summary. Does not edit the source bank or user data.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BANK = ROOT / "assets" / "deda_traffic_500_bank_ar_v1.json"

TOPICS = [
    "regulatory", "warning", "guidance", "signals", "priority",
    "pedestrian", "speed", "lanes", "roundabouts", "parking",
    "night", "weather", "rural", "motorcycles", "trucks",
    "restraints", "vehicle", "awareness", "emergency", "conduct",
]
SIGNS_FROM_ORIGINAL_BANK = {
    "DEDA-TRF-0001", "DEDA-TRF-0003", "DEDA-TRF-0004",
    "DEDA-TRF-0005", "DEDA-TRF-0006", "DEDA-TRF-0007",
    "DEDA-TRF-0020", "DEDA-TRF-0027", "DEDA-TRF-0028",
    "DEDA-TRF-0029", "DEDA-TRF-0032", "DEDA-TRF-0077",
    "DEDA-TRF-0078", "DEDA-TRF-0080",
}
LEGACY_EXTRA_SIGNS = {
    "DEDA-TRF-0002", "DEDA-TRF-0015", "DEDA-TRF-0018",
    "DEDA-TRF-0026", "DEDA-TRF-0030", "DEDA-TRF-0052",
    "DEDA-TRF-0076", "DEDA-TRF-0103", "DEDA-TRF-0108",
}
# Signals 76-78 and stop line 80 have custom scenario-specific drawings in QA.
SPECIAL_ILLUSTRATIONS = {
    "DEDA-TRF-0076", "DEDA-TRF-0077",
    "DEDA-TRF-0078", "DEDA-TRF-0080",
}


def normalize(value: str) -> str:
    value = "".join(c for c in unicodedata.normalize("NFKD", value)
                    if not unicodedata.combining(c))
    value = re.sub(r"[إأآٱ]", "ا", value).replace("ى", "ي")
    return re.sub(r"[^\w]+", "", value, flags=re.UNICODE).lower()


def audit(rows: list[dict]) -> tuple[list[dict], dict]:
    if len(rows) != 500:
        raise ValueError(f"expected 500 questions, got {len(rows)}")
    seen_ids = set()
    seen_questions = defaultdict(list)
    topic_counts = Counter()
    records = []
    invalid = []
    for index, q in enumerate(rows, 1):
        ident = q.get("question_id", "")
        topic = q.get("topic_id", "")
        answer_index = q.get("correct_index")
        opts = q.get("options_ar")
        question = q.get("question_ar")
        explanation = q.get("explanation_ar")
        structural = []
        if ident != f"DEDA-TRF-{index:04d}" or ident in seen_ids:
            structural.append("INVALID_OR_DUPLICATE_QUESTION_ID")
        seen_ids.add(ident)
        expected_topic = TOPICS[(index - 1) // 25]
        if topic != expected_topic:
            structural.append("WRONG_TOPIC_ASSIGNMENT")
        if not isinstance(question, str) or not question.strip():
            structural.append("EMPTY_QUESTION")
        if not isinstance(explanation, str) or not explanation.strip():
            structural.append("EMPTY_EXPLANATION")
        if not isinstance(opts, list) or len(opts) != 5 or not all(
            isinstance(x, str) and x.strip() for x in opts
        ):
            structural.append("NOT_FIVE_CHOICES")
            opts = [""] * 5
        if len({normalize(x) for x in opts}) != 5:
            structural.append("DUPLICATE_CHOICES")
        if not isinstance(answer_index, int) or answer_index not in range(5):
            structural.append("INVALID_CORRECT_INDEX")
            answer_index = -1
        q_key = normalize(question or "")
        seen_questions[q_key].append(ident)
        topic_counts[topic] += 1

        if ident in SPECIAL_ILLUSTRATIONS:
            illustration = "SCENARIO_DRAWING_QA"
        elif ident in SIGNS_FROM_ORIGINAL_BANK | LEGACY_EXTRA_SIGNS:
            illustration = "STOCK_SIGN_GLYPH_REQUIRES_LOCAL_VALIDATION"
        else:
            illustration = "TOPIC_PICTOGRAM_EDUCATIONAL_NOT_OFFICIAL"
        # Flag direct answer-label leaks for editorial review; no automated
        # semantic classifier can certify accuracy of 500 driving answers.
        quoted = re.findall(r"«([^»]+)»", question or "")
        correct = opts[answer_index] if answer_index >= 0 else ""
        leak = any(
            normalize(label) in normalize(correct)
            or (len(normalize(label)) >= 7 and
                any(normalize(label) in normalize(x) for x in opts))
            for label in quoted
        )
        flags = list(structural)
        if leak:
            flags.append("QUOTED_SIGN_NAME_MAY_LEAK_ANSWER")
        if illustration == "TOPIC_PICTOGRAM_EDUCATIONAL_NOT_OFFICIAL":
            flags.append("SCENARIO_ARTWORK_NOT_PRESENT")
        # Independent traffic specialist must validate the source and the
        # four distractors, regardless of the automatic check results.
        flags += ["OFFICIAL_REFERENCE_MISSING",
                  "INDEPENDENT_TRAFFIC_EDITOR_REVIEW_PENDING"]
        invalid.extend((ident, issue) for issue in structural)
        records.append({
            "question_id": ident,
            "topic_id": topic,
            "question_ar": question,
            "option_1": opts[0],
            "option_2": opts[1],
            "option_3": opts[2],
            "option_4": opts[3],
            "option_5": opts[4],
            "correct_option_number": answer_index + 1,
            "correct_answer": correct,
            "explanation_ar": explanation,
            "artwork_type": illustration,
            "source_authority_reference": "",
            "editor_name": "",
            "editor_review_date": "",
            "review_status": "PENDING_INDEPENDENT_TRAFFIC_REVIEW",
            "flags": " | ".join(flags),
        })
    duplicate_question_groups = [
        ids for ids in seen_questions.values() if len(ids) > 1
    ]
    summary = {
        "bank_questions": len(records),
        "topics": dict(sorted(topic_counts.items())),
        "five_answer_records": sum(
            len(q.get("options_ar", [])) == 5 for q in rows),
        "structural_errors": invalid,
        "exact_duplicate_question_groups": duplicate_question_groups,
        "potential_answer_leaks": [
            z["question_id"] for z in records
            if "QUOTED_SIGN_NAME_MAY_LEAK_ANSWER" in z["flags"]],
        "topic_pictograms_not_official_signs": sum(
            z["artwork_type"] ==
            "TOPIC_PICTOGRAM_EDUCATIONAL_NOT_OFFICIAL" for z in records),
        "scenario_specific_illustrations": len(SPECIAL_ILLUSTRATIONS),
        "source_reviewed_rows": 0,
        "independently_approved_for_publication": 0,
        "publication_blocked": True,
        "warning": (
            "Not independently checked against Iraqi traffic law or standards."
            " The 500 answer options contain generated distractors. "
            "PRIVATE QA ONLY until every row has citation and specialist sign-off."
        ),
    }
    return records, summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()
    rows = json.loads(BANK.read_text(encoding="utf-8"))["questions"]
    records, summary = audit(rows)
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    args.summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2)
                            + "\n", encoding="utf-8")
    print(json.dumps({
        "questions": summary["bank_questions"],
        "choices": summary["five_answer_records"],
        "structuralErrors": len(summary["structural_errors"]),
        "potentialAnswerLeaks": len(summary["potential_answer_leaks"]),
        "topicOnlyPictograms": summary["topic_pictograms_not_official_signs"],
        "reviewedForPublication": 0,
        "publicationBlocked": True,
    }, ensure_ascii=False))
    if summary["structural_errors"] or duplicate_question_groups_exist(summary):
        raise SystemExit("Structural source-bank audit failed.")


def duplicate_question_groups_exist(summary):
    return bool(summary["exact_duplicate_question_groups"])


if __name__ == "__main__":
    main()
