#!/usr/bin/env python3
"""从 Lucide 图标字体生成官网用的子集字体与样式表。

图标矢量数据取自 pub 依赖 lucide_icons_flutter（与应用使用同一套字形），
不手工绘制、不从截图描摹。Lucide 图标按 ISC 许可证分发，声明见
site/licenses.html。

用法（仓库根目录）：
    python scripts/icons/gen_lucide_subset.py
"""

import json
import os
import re
import sys

from fontTools import subset

# 官网模拟窗口用到的图标，名称与 Lucide 字形名一致。
ICONS = [
    "message-circle",
    "message-circle-plus",
    "message-square-plus",
    "search",
    "languages",
    "folder",
    "monitor",
    "sun",
    "moon",
    "settings",
    "menu",
    "plus",
    "paperclip",
    "brain",
    "sparkles",
    "copy",
    "volume-2",
    "image",
    "tool-case",
    "book-open",
    "globe",
    "wand-2",
    "history",
    "link",
    "tag",
    "arrow-up",
    "arrow-down",
    "chevron-left",
    "chevron-right",
    "chevron-up",
    "chevron-down",
    "chevrons-up",
    "chevrons-down",
    "rotate-cw",
    "refresh-cw",
    "ellipsis",
    "sliders-horizontal",
    "x",
    # 输入条工具行（取值出处：lib/features/home/widgets/chat_input_bar.dart 的
    # _buildResponsiveLeftActions 与桌面分支右侧按钮）
    "boxes",
    "folder-code",
    "zap",
    "camera",
    # 字体里没有 layers 与 wand-sparkles 两个名字，取最接近的既有字形：
    # layers-2 对应应用的 Lucide.Layers，技能用已有的 wand-2。
    "layers-2",
    "eraser",
    "map",
    "eye",
    "mic",
    "package-2",
]


def package_dir(name: str) -> str:
    """按 .dart_tool/package_config.json 解析依赖包目录。"""
    cfg = os.path.join(".dart_tool", "package_config.json")
    if not os.path.exists(cfg):
        sys.exit("找不到 .dart_tool/package_config.json，请先执行 flutter pub get")
    with open(cfg, encoding="utf-8") as f:
        data = json.load(f)
    for pkg in data["packages"]:
        if pkg["name"] != name:
            continue
        uri = pkg["rootUri"]
        if uri.startswith("file:///"):
            path = uri[len("file:///") :]
        else:
            path = os.path.normpath(os.path.join(".dart_tool", uri))
        return path.replace("/", os.sep)
    sys.exit(f"依赖包里没有 {name}")


def main() -> None:
    pkg = package_dir("lucide_icons_flutter")
    src = os.path.join(pkg, "assets", "lucide.ttf")
    if not os.path.exists(src):
        sys.exit(f"找不到源字体：{src}")

    os.makedirs("site", exist_ok=True)
    out_font = os.path.join("site", "lucide-subset.woff2")
    out_css = os.path.join("site", "lucide-icons.css")

    opts = subset.Options()
    opts.flavor = "woff2"
    opts.layout_features = []
    opts.name_IDs = []
    opts.notdef_outline = True

    font = subset.load_font(src, opts)
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(glyphs=ICONS)
    subsetter.subset(font)
    subset.save_font(font, out_font, opts)
    font.close()

    lines = [
        "/* Lucide 图标字体子集 —— 由 scripts/icons/gen_lucide_subset.py 生成，勿手工编辑。",
        "   图标按 ISC 许可证分发，声明见 licenses.html。 */",
        "@font-face {",
        '  font-family: "Lucide";',
        '  src: url("lucide-subset.woff2") format("woff2");',
        "  font-weight: normal;",
        "  font-style: normal;",
        "  font-display: block;",
        "}",
        "",
        ".lic {",
        '  font-family: "Lucide";',
        "  font-style: normal;",
        "  font-weight: normal;",
        "  font-variant: normal;",
        "  line-height: 1;",
        "  display: inline-block;",
        "  vertical-align: middle;",
        "  -webkit-font-smoothing: antialiased;",
        "  -moz-osx-font-smoothing: grayscale;",
        "}",
        "",
    ]

    # 码点表与字形同名，用字体自身的 cmap 反查，避免硬编码。
    from fontTools.ttLib import TTFont

    ref = TTFont(src)
    cmap = ref.getBestCmap()
    by_name = {v: k for k, v in cmap.items()}
    for name in ICONS:
        cp = by_name.get(name)
        if cp is None:
            sys.exit(f"字体里没有字形 {name}")
        lines.append('.lic-%s::before { content: "\\%x"; }' % (name, cp))

    with open(out_css, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    size = os.path.getsize(out_font)
    print(f"已生成 {out_font}（{size} 字节，{len(ICONS)} 个字形）")
    print(f"已生成 {out_css}")


if __name__ == "__main__":
    main()
