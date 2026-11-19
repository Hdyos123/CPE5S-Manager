import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'OPPOCPE.xcodeproj/project.pbxproj'
s = open(path).read()

depth = 0
instr = False
esc = False
for c in s:
    if instr:
        if esc:
            esc = False
        elif c == '\\':
            esc = True
        elif c == '"':
            instr = False
        continue
    if c == '"':
        instr = True
    elif c in '({':
        depth += 1
    elif c in ')}':
        depth -= 1
    if depth < 0:
        sys.exit('unbalanced parens')

if depth != 0:
    sys.exit('unbalanced (final depth %d)' % depth)

ids = re.findall(r'^\t\t([0-9A-F]{24}) ', s, re.M)
if len(ids) != len(set(ids)):
    sys.exit('duplicate object ids')

print('pbxproj OK: %d objects' % len(ids))
