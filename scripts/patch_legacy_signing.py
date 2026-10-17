#!/usr/bin/env python3
"""把历史 tag 的 android/app/build.gradle.kts 从 debug 签名改写为读取 release 签名。

仅在使用 workflow_dispatch 的 resign_tag 输入重建历史版本时调用。
签名材料从环境变量读取（CI 由 GitHub Secrets 注入）。
"""

import pathlib
import re
import sys

GRADLE = pathlib.Path("android/app/build.gradle.kts")

SIGNING_BLOCK = '''android {
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("COMICREALM_STORE_FILE"))
            storePassword = System.getenv("COMICREALM_STORE_PASSWORD")
            keyAlias = System.getenv("COMIC_REALM_KEY_ALIAS")
            keyPassword = System.getenv("COMIC_REALM_KEY_PASSWORD")
        }
    }
'''


def main() -> int:
    if not GRADLE.exists():
        print(f"::error::找不到 {GRADLE}", file=sys.stderr)
        return 1

    src = GRADLE.read_text(encoding="utf-8")
    original = src

    # 1) 若没有 signingConfigs { ... } 块，就在 android { 后插入 release 配置。
    #    注意：旧版本里有 signingConfigs.getByName("debug") 这种调用，
    #    光判断 "signingConfigs" 字样会误判为“已存在”，必须匹配带大括号的块声明。
    has_block = re.search(r"signingConfigs\s*\{", src) is not None
    if not has_block:
        if "android {" not in src:
            print("::error::build.gradle.kts 结构异常，找不到 android { 块", file=sys.stderr)
            return 1
        src = src.replace("android {", SIGNING_BLOCK, 1)

    # 2) 把 release 构建类型里的 debug 签名改为 release
    src = src.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )

    if src == original:
        print("警告：未检测到需要改写的内容（可能已是 release 签名）")

    GRADLE.write_text(src, encoding="utf-8")
    print("已改写签名配置为 release")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
