from pathlib import Path
import re
from collections import defaultdict

lib = Path(__file__).resolve().parent.parent  # lib/

IMPORT_RE = re.compile(r'^import\s+["\']([^"\']+)["\'];', re.M)
SCREEN_CLASS_RE = re.compile(r'^class\s+(\w+)\s+extends\s+StatefulWidget\b', re.M)
WIDGET_CLASS_RE = re.compile(r'^class\s+(\w+)\s+extends\s+State<', re.M)


def analyze():
    modules: dict[str, dict[str, object]] = {}
    for path in sorted(lib.rglob('*.dart')):
        rel = str(path.relative_to(lib))
        text = path.read_text(errors='replace')
        imports = []
        for m in IMPORT_RE.finditer(text):
            dep = m.group(1)
            if dep.startswith('package:') or dep.startswith('dart:'):
                continue
            dep = dep.strip()
            if dep:
                imports.append(dep)
        screens = [m.group(1) for m in SCREEN_CLASS_RE.finditer(text)]
        widgets = [m.group(1) for m in WIDGET_CLASS_RE.finditer(text)]
        modules[rel] = {
            'imports': imports,
            'screens': screens,
            'widgets': widgets,
            'bytes': path.stat().st_size,
            'lines': text.count('\n') + 1,
        }
    return modules


if __name__ == '__main__':
    for rel, info in sorted(analyze().items()):
        print(f'{rel}\t{info["bytes"]}\t{info["lines"]}\t{info["screens"]}\t{info["widgets"]}\t{info["imports"]}')
