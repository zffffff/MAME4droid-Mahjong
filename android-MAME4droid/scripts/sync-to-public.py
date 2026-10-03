#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从私有仓某提交导出「公开正式版」树，推到 remote `public` 的 main。

- 不改当前工作区；私有 main 上的自用 docs / .cursor 保持不动。
- 在临时 worktree 里删掉仅私有路径、收束 README，再 commit 并 push public。

用法（仓库根目录）:
  python android-MAME4droid/scripts/sync-to-public.py --dry-run
  python android-MAME4droid/scripts/sync-to-public.py
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

# scripts/ → android-MAME4droid/ → repo root
ROOT = Path(__file__).resolve().parents[2]

# 仅私有：自用 / 运营向 / 本机路径 / 签名操作说明 / Agent 规则
# 玩家向「用户更新说明」也属运营表述，不必强加给公开克隆者
PRIVATE_ONLY_PATHS = [
    "docs/宣传要点.md",
    "docs/用户更新说明.md",
    "docs/两版分工.md",
    "docs/知识库.md",
    "docs/整合勿丢内容.md",
    "docs/选台资源与签名.md",
    ".cursor/rules/feijuchang-mahjong.mdc",
]


def run(
    cmd: list[str],
    cwd: Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(cwd or ROOT),
        check=check,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )


def git_out(cmd: list[str], cwd: Path | None = None) -> str:
    return run(["git", *cmd], cwd=cwd).stdout.strip()


def public_readme(src_readme: str) -> str:
    header = """# 飞剧场怀旧麻将

基于 [MAME4droid (Current)](https://github.com/seleuco/MAME4droid-Current) 的麻将特供版（GPL）。原作者 David Valdeita (Seleuco)。

| 产品 | 包名 |
|------|------|
| 飞剧场怀旧麻将（完整版） | `com.feijuchang.mahjong` |
| 基础飞剧场 | `com.feijuchang.mahjong.basic` |

不内置 ROM；首次启动会自动安装按键包资源。按键包亦随本仓开源。

**开源与分发：** [docs/开源与合规.md](docs/开源与合规.md)（卖或送 APK 时，下载页请同时附上本仓库链接）  
**更新日志：** [docs/更新日志.md](docs/更新日志.md)

源码：https://github.com/zffffff/MAME4droid-Mahjong

**主页：** https://roxyweal.work  
**B 站：** https://space.bilibili.com/486651839  
**Telegram：** https://t.me/ai_Meishi  
**公众号：** 路边漫画（请在微信内搜索关注）

---
"""
    marker = "# Upstream: MAME4droid (Current)"
    if marker in src_readme:
        return header + src_readme[src_readme.index(marker) :]
    return header


def main() -> int:
    ap = argparse.ArgumentParser(description="Sync slim formal-release tree to remote public")
    ap.add_argument("--ref", default="HEAD", help="source commit (default HEAD)")
    ap.add_argument("--remote", default="public", help="git remote for public repo")
    ap.add_argument("--branch", default="main", help="public branch to update")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.remote not in git_out(["remote"]).splitlines():
        print(f"ERROR: remote '{args.remote}' missing", file=sys.stderr)
        return 2

    src = git_out(["rev-parse", args.ref])
    print(f"source: {git_out(['log', '-1', '--oneline', src])}")

    if args.dry_run:
        for p in PRIVATE_ONLY_PATHS:
            ok = run(["git", "cat-file", "-e", f"{src}:{p}"], check=False).returncode == 0
            print(f"  remove {'(present)' if ok else '(absent)':10} {p}")
        print(f"push → {args.remote}/{args.branch} (force-with-lease if diverged)")
        return 0

    readme_src = git_out(["show", f"{src}:README.md"])
    msg = (
        f"public: slim formal snapshot from {src[:7]}\n\n"
        "Remove private-only docs/rules from the published tree; "
        "keep buildable sources, LICENSE/NOTICE, and compliance notes.\n"
        "Full developer docs remain on the private product remote only."
    )

    with tempfile.TemporaryDirectory(prefix="feiju-public-") as tmp:
        tmp_path = Path(tmp)
        add = run(["git", "worktree", "add", "--detach", str(tmp_path), src], check=False)
        if add.returncode != 0:
            print(add.stderr, file=sys.stderr)
            return add.returncode
        try:
            for rel in PRIVATE_ONLY_PATHS:
                if (tmp_path / rel).exists():
                    run(["git", "rm", "-rf", rel], cwd=tmp_path)

            cursor = tmp_path / ".cursor"
            if cursor.is_dir() and not any(cursor.rglob("*")):
                run(["git", "rm", "-rf", ".cursor"], cwd=tmp_path, check=False)
            elif cursor.is_dir():
                # remove empty rules dir / .cursor if only empty leftovers
                rules = cursor / "rules"
                if rules.is_dir() and not any(rules.iterdir()):
                    run(["git", "rm", "-rf", ".cursor"], cwd=tmp_path, check=False)

            (tmp_path / "README.md").write_text(
                public_readme(readme_src), encoding="utf-8", newline="\n"
            )
            run(["git", "add", "README.md"], cwd=tmp_path)
            # commit only if something staged
            st = git_out(["status", "--porcelain"], cwd=tmp_path)
            if not st:
                print("nothing to change vs source tree")
                return 1
            run(["git", "commit", "-m", msg], cwd=tmp_path)
            new_sha = git_out(["rev-parse", "HEAD"], cwd=tmp_path)
            docs = git_out(["ls-tree", "--name-only", "HEAD:docs"], cwd=tmp_path)
            print(f"public commit: {new_sha[:7]}")
            print("docs/:\n" + "\n".join(f"  {x}" for x in docs.splitlines()))

            # prefer lease; fall back to --force for first slim sync if lease fails
            push = run(
                [
                    "git",
                    "push",
                    "--force-with-lease",
                    args.remote,
                    f"HEAD:refs/heads/{args.branch}",
                ],
                cwd=tmp_path,
                check=False,
            )
            if push.returncode != 0:
                print(push.stderr or push.stdout)
                print("retry with --force ...")
                push = run(
                    ["git", "push", "--force", args.remote, f"HEAD:refs/heads/{args.branch}"],
                    cwd=tmp_path,
                    check=False,
                )
            if push.returncode != 0:
                print(push.stderr or push.stdout, file=sys.stderr)
                return push.returncode
            print(f"OK → {args.remote}/{args.branch} @ {new_sha[:7]}")
            print("私有工作区未改。公开历史里旧 commit 仍可能含已删文件；当前 main 树已瘦身。")
        finally:
            run(["git", "worktree", "remove", "--force", str(tmp_path)], check=False)

    return 0


if __name__ == "__main__":
    sys.exit(main())
