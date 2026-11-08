import sys
s = open('CPE5S.xcodeproj/project.pbxproj').read()
stack = []; in_str = False; esc = False
for ch in s:
    if in_str:
        if esc: esc = False
        elif ch == '\\': esc = True
        elif ch == '"': in_str = False
        continue
    if ch == '"': in_str = True
    elif ch in '{(': stack.append(ch)
    elif ch in '})':
        want = '{' if ch == '}' else '('
        if not stack or stack.pop() != want:
            sys.exit('unbalanced')
if stack: sys.exit('unclosed')
print('pbxproj OK')
