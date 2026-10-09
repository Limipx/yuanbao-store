#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
迷你世界 UGC 3.0 组件脚本 · 交付前自动检查

用法:
    python3 check.py <脚本.lua> [更多.lua...]
    python3 check.py --dir /path/to/dir

输出:  ❌ 致命（必须修）  ⚠️ 警告（建议修）  ✓ 通过
退出码: 0=无致命  1=有致命
"""
import sys, os, re, glob

class Issue:
    def __init__(self, lvl, no, msg, line=None):
        self.lvl, self.no, self.msg, self.line = lvl, no, msg, line


def strip_comments(src):
    """把 Lua 注释替换为空（保留行号与行长结构），避免注释里的示例代码被误报。"""
    out = []
    for line in src.split("\n"):
        # 整行注释
        st = line.lstrip()
        if st.startswith("--"):
            out.append("")
            continue
        # 行尾注释：粗暴但够用（本技能只做结构检查，不解析字符串）
        i = line.find("--")
        if i >= 0:
            out.append(line[:i])
        else:
            out.append(line)
    return "\n".join(out)


def check(path):
    try:
        src = open(path, encoding="utf-8", errors="replace").read()
    except Exception as e:
        return [Issue("❌", 0, "读文件失败: %s" % e)]
    lines = src.split("\n")
    code = strip_comments(src)   # 去注释后的代码，用于结构检查
    out = []
    def L(sub):
        for i, l in enumerate(lines, 1):
            if sub in l: return i
        return None

    # 1. local Script = {}
    if not re.search(r'^\s*local\s+Script\s*=\s*\{\}', src, re.M):
        out.append(Issue("❌", 1, "缺少 local Script = {}"))

    # 2. return Script
    tail = "\n".join(lines[-8:])
    if not re.search(r'^[ \t]*return[ \t]+Script[ \t]*$', tail, re.M):
        out.append(Issue("❌", 2, "文件末尾缺少 return Script"))

    # 3. openFunctions = openFnArgs 互赋值
    for m in re.finditer(r'openFunctions\s*=\s*Script\.openFnArgs|openFnArgs\s*=\s*Script\.openFunctions', code):
        out.append(Issue("❌", 3, "登记表互相赋值（Script 表内出现非函数引用）",
                         src[:m.start()].count("\n") + 1))

    # 4. 运行时读 Script.propertys[x].default / .value
    for m in re.finditer(r'Script\.propertys\s*\[[^\]]*\]\s*\.\s*(default|value)', code):
        out.append(Issue("❌", 4, "运行时读 Script.propertys[x].%s，应读 self[x]" % m.group(1),
                         src[:m.start()].count("\n") + 1))
    for m in re.finditer(r'Script\.propertys\s*\.\s*\w+\s*\.\s*(default|value)', code):
        out.append(Issue("❌", 4, "运行时读 Script.propertys.x.%s，应读 self.x" % m.group(1),
                         src[:m.start()].count("\n") + 1))

    # 5. GetAllValue 的 playerId
    for m in re.finditer(r'GetAllValue\s*\(\s*(?:Data\.Table\s*,\s*)?([^,)]+)\s*,\s*([^)]*)\)', code):
        pid = m.group(2).strip()
        if pid and pid not in ("nil", "0", "playerId", "pid"):
            try:
                if float(pid) != 0:
                    out.append(Issue("❌", 5,
                        "GetAllValue 的 playerId=%s（非0=私人变量），二维表应传 nil 或 0" % pid,
                        src[:m.start()].count("\n") + 1))
            except ValueError:
                pass

    # 6. propertys / openFnArgs 必须在顶层
    for kw in ("propertys", "openFnArgs", "openFunctions"):
        m = re.search(r'^([ \t]*)Script\.%s\s*=' % kw, src, re.M)
        if m and len(m.group(1)) > 0:
            out.append(Issue("❌", 6, "Script.%s 有缩进（被搬进函数体了），必须在顶层" % kw,
                             src[:m.start()].count("\n") + 1))

    # 7. arrayWrapper 定义在 openFnArgs 之前
    iw = code.find("arrayWrapper")
    io_ = code.find("Script.openFnArgs")
    if iw >= 0 and io_ >= 0 and iw > io_:
        out.append(Issue("❌", 7, "arrayWrapper 定义在 openFnArgs 之后（returnType 会取到 nil）"))

    # 8. 惰性初始化
    nfn = len(re.findall(r'function\s+Script:\w+\s*\(', src))
    if nfn > 3 and not re.search(r'ensureInit|COMPONENT_SELF\s*==\s*nil|#IDS\s*==\s*0', src):
        out.append(Issue("⚠️", 8, "未见惰性初始化（开放函数依赖 OnStart 成功，OnStart 失败则永久空）"))

    # 9. On* 改名
    for m in re.finditer(r'function\s+Script:(\w+)\s*\(', src):
        nm = m.group(1)
        if nm.startswith("On") and nm not in ("OnStart", "OnDestroy", "OnUpdate", "OnEvent"):
            out.append(Issue("⚠️", 9, "生命周期类函数名 %s 疑似被改名（引擎按名字调用）" % nm,
                             src[:m.start()].count("\n") + 1))
    if not re.search(r'function\s+Script:OnStart', src):
        out.append(Issue("⚠️", 9, "没有 OnStart"))

    # 10. 登记表键 vs 函数定义名
    fns = set(re.findall(r'function\s+Script:(\w+)\s*\(', src))
    m = re.search(r'Script\.openFnArgs\s*=\s*\{(.*?)(?:\n\}|$)', code, re.S)
    if m:
        keys = set(re.findall(r'^[ \t]{4}(\w+)[ \t]*=[ \t]*\{', m.group(1), re.M))
        keys -= {"returnType", "displayName", "params", "tips", "desc"}
        miss = keys - fns
        for k in sorted(miss):
            out.append(Issue("⚠️", 10, "登记表键 %s 找不到对应函数定义" % k))
        extra = fns - keys - {"OnStart", "OnDestroy"}
        # 只提示：可能是 local 辅助函数、或键名大小写不同，不算错
        if extra and len(extra) <= 6:
            for k in sorted(extra):
                out.append(Issue("💡", 10, "函数 %s 未在 openFnArgs 找到同名键（确认是否为辅助函数）" % k))

    return out

def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); return 2
    files = []
    if args[0] == "--dir":
        files = glob.glob(os.path.join(args[1], "**", "*.lua"), recursive=True)
    else:
        for a in args:
            files += glob.glob(a) if any(c in a for c in "*?") else [a]
    bad = 0
    for f in files:
        if not os.path.exists(f):
            print("跳过（不存在）: %s" % f); continue
        iss = check(f)
        fatal = [i for i in iss if i.lvl == "❌"]
        bad += len(fatal)
        print("\n── %s  （%d 行）" % (f, open(f, encoding="utf-8", errors="replace").read().count("\n") + 1))
        if not iss:
            print("  ✓ 全部通过")
        for i in iss:
            loc = "  L%d" % i.line if i.line else ""
            print("  %s [%d]%s  %s" % (i.lvl, i.no, loc, i.msg))
    print("\n" + ("致命错误 %d 个，必须修" % bad if bad else "✓ 无致命错误，可交付"))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
