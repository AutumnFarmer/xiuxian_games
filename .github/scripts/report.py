"""把编译和测试结果写成 GitHub 注释（annotations），方便在 Actions 页面和 API 里直接看到错误。"""
import os
import re

def read(name):
    try:
        with open(name, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []

def esc(s):
    return s.replace("%", "%25").replace("\r", "").replace("\n", "%0A")

root = os.getcwd() + "/"
build = read("build.log")
test = read("test.log")
bs = os.environ.get("BUILD_STATUS", "?")
ts = os.environ.get("TEST_STATUS", "skipped")

pat = re.compile(r"^(/[^:]+):(\d+):(\d+): (error|warning): (.*)$")
errors, warnings, seen = [], [], set()
for line in build + test:
    m = pat.match(line)
    if not m:
        continue
    f, l, c, kind, msg = m.groups()
    key = (f, l, msg)
    if key in seen:
        continue
    seen.add(key)
    rel = f.replace(root, "")
    (errors if kind == "error" else warnings).append(f"{rel}:{l}:{c}: {msg}")

# 其他形式的错误（链接、资源、测试失败）
extra = []
lines = build + test
for k, line in enumerate(lines):
    if line.startswith("Undefined symbols") or line.startswith("ld: "):
        for t in lines[k:k + 6]:
            if t.strip() and t.strip() not in extra:
                extra.append(t.strip())
for line in build + test:
    s = line.strip()
    if (s.startswith("error:") or " error: " in s and not pat.match(line)) and s not in extra:
        extra.append(s)
    if re.search(r"Test Case .* failed|XCTAssert.*failed|Fatal error", s) and s not in extra:
        extra.append(s)

def emit(kind, title, items, per=15, limit=9):
    for i in range(0, min(len(items), per * limit), per):
        chunk = "\n".join(items[i:i + per])[:3800]
        print(f"::{kind} title={title} {i // per + 1}::{esc(chunk)}")

xcode = " / ".join(l.strip() for l in read("xcode_version.txt") if l.strip())
summary = f"build={bs} test={ts} errors={len(errors)} warnings={len(warnings)} extra={len(extra)} | {xcode}"
print(summary)
print(f"::notice title=RESULT::{summary}")
emit("error", "compile", errors)
emit("error", "other", extra[:40], per=10, limit=4)
emit("warning", "warnings", warnings[:30], per=15, limit=2)

with open(os.environ.get("GITHUB_STEP_SUMMARY", "/dev/null"), "a") as out:
    out.write(f"## {summary}\n\n")
    for e in errors[:200]:
        out.write(f"- {e}\n")

if bs != "0" or (ts not in ("0", "skipped")):
    raise SystemExit(1)
