#!/usr/bin/env python3
"""Check that every file path referenced in chapter docs actually exists.

The Ch 4 review round shipped three phantom script paths and Ch 10 referenced
a native/streams.sql that did not exist. This check makes that class of error
mechanical instead of a reviewer catch (companion-scripts standard, section 7).

Modes:
  python tools/check_path_alignment.py
      Repo mode: scans every chapters/chapter*/ README.md (and any other
      tracked .md under chapters/) for path-like references and asserts each
      resolves inside the repo.

  python tools/check_path_alignment.py --manuscripts "/path/to/book/chapters"
      Additionally scans the (private, out-of-repo) chapter manuscripts
      Chapter_NN_*.md and checks their repo path references too.

Intentional non-files (illustrative examples in prose) go in
tools/path_alignment_allowlist.txt, one substring per line.
"""
import argparse, re, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PATH_RX = re.compile(
    r"[\w./-]*(?:chapters/chapter\d+|setup|sql|commands|prompts|snowpark[\w]*|dbt|"
    r"sqlmesh|airflow|prefect|dagster|jobs|data|native|infra|migrations|"
    r"techflow_pipeline|parity|orchestration|ci|kafka|archive|coco-skills|tools)"
    r"[\w./-]*\.(?:sql|py|sh|yml|yaml|json|toml|csv|avro|txt|tf|ini|md|jar)\b")

def load_allowlist():
    f = REPO / "tools" / "path_alignment_allowlist.txt"
    if not f.exists():
        return []
    return [l.strip() for l in f.read_text().splitlines()
            if l.strip() and not l.strip().startswith("#")]

def tracked_files():
    """Git-tracked files when available (readers' view); rglob fallback."""
    try:
        out = subprocess.run(["git", "ls-files"], cwd=REPO, capture_output=True,
                             text=True, check=True).stdout.splitlines()
        return set(out)
    except Exception:
        return {str(p.relative_to(REPO)) for p in REPO.rglob("*")
                if p.is_file() and ".git" not in p.parts and ".venv" not in p.parts}

def check_doc(doc: Path, chapter_dir: str | None, repo_files: set, allow) -> list:
    misses = []
    text = doc.read_text(encoding="utf-8", errors="replace")
    for m in PATH_RX.finditer(text):
        raw = m.group(0)
        # skip URLs and repo-external references
        start = max(0, m.start() - 24)
        if "://" in text[start:m.start()] or raw.startswith("github.com"):
            continue
        if any(a in raw for a in allow):
            continue
        variants = {raw, raw.lstrip("./"), "." + raw.lstrip("./")}
        cands = set()
        for v in variants:
            cands.add(v)
            if chapter_dir and not v.startswith("chapters/") and not v.startswith("."):
                cands.add(f"{chapter_dir}/{v}")
        def resolves(c):
            if c in repo_files or (c + ".example") in repo_files:
                return True
            return any(rf.endswith("/" + c) for rf in repo_files)
        if not any(resolves(c) for c in cands):
            misses.append(raw)
    return sorted(set(misses))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manuscripts", help="Directory holding Chapter_NN_*.md manuscripts")
    args = ap.parse_args()

    allow = load_allowlist()
    repo_files = tracked_files()
    failures = 0

    docs = [REPO / f for f in repo_files
            if f.startswith("chapters/chapter") and f.endswith(".md")
            and "archive/" not in f and "dbt_packages/" not in f]
    for readme in sorted(docs):
        chapter_dir = "/".join(readme.relative_to(REPO).parts[:2])
        misses = check_doc(readme, chapter_dir, repo_files, allow)
        for ref in misses:
            print(f"MISS  {readme.relative_to(REPO)}: {ref}")
            failures += 1

    if args.manuscripts:
        mdir = Path(args.manuscripts)
        for md in sorted(mdir.glob("Chapter_*.md")):
            ch = re.match(r"Chapter_(\d+)", md.name)
            chapter_dir = f"chapters/chapter{int(ch.group(1))}" if ch else None
            misses = check_doc(md, chapter_dir, repo_files, allow)
            for ref in misses:
                print(f"MISS  {md.name}: {ref}")
                failures += 1

    if failures:
        print(f"\n{failures} unresolved path reference(s).")
        sys.exit(1)
    print("All path references resolve.")

if __name__ == "__main__":
    main()
