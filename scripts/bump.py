#!/usr/bin/env python3
# Auto-bump build (CURRENT_PROJECT_VERSION +1) and version patch (MARKETING_VERSION x.y.Z+1)
# in project.yml. Run before each `make ipa` so every build is newer than the last.
import re

P = "project.yml"
s = open(P).read()

b = int(re.search(r'CURRENT_PROJECT_VERSION: "(\d+)"', s).group(1)) + 1
s = re.sub(r'CURRENT_PROJECT_VERSION: "\d+"', f'CURRENT_PROJECT_VERSION: "{b}"', s, count=1)

m = re.search(r'MARKETING_VERSION: "(\d+)\.(\d+)\.(\d+)"', s)
nv = f"{m.group(1)}.{m.group(2)}.{int(m.group(3)) + 1}"
s = re.sub(r'MARKETING_VERSION: "\d+\.\d+\.\d+"', f'MARKETING_VERSION: "{nv}"', s, count=1)

open(P, "w").write(s)
print(f"→ version {nv}, build {b}")
