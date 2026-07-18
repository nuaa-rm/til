# 第三章：Git 高级特性

## 概述

本章聚焦于出了问题之后的处理手段：用 `revert` 安全撤销已发布的 commit、用 `cherry-pick` 从其他分支摘取修复、用 `worktree` 同时在两个分支上工作而不需要 `stash`。`git bisect` 作为定位"哪个 commit 引入了 bug"的利器单独讲解。CLion 的 Git Log 工具是主要操作界面，命令行作为补充。

练习文件：`ch3_git_advanced/setup_repo.sh` + `buggy_calc.cpp`

---

## 3.1 环境准备

```bash
cd ch3_git_advanced
chmod +x setup_repo.sh
./setup_repo.sh
# 输出：Repository ready at: .../practice_repo
cd practice_repo
git log --oneline
```

预期历史（从新到旧）：
```
e5f3a1c (HEAD -> main) feat: add std_dev helper
3d8b2f0 refactor: simplify variance denominator   ← BUG 在这里
a1c4e22 refactor: clarify population variance comment
7b9d501 test: add self-test for statistics functions
f2e0c3a feat: add mean, variance, median_sorted
```

另有分支 `fix/variance-denominator` 包含正确修复。

---

## 3.2 git bisect：二分定位 bug

### 概念

`git bisect` 用二分搜索在提交历史中自动缩小"引入 bug 的 commit"范围。每次 checkout 一个版本，你测试后告诉 Git "好" 或 "坏"，Git 继续二分，直到精确定位。

**时间复杂度：** N 个 commit 只需 log₂(N) 次测试。100 个 commit 只需 7 次。

### CLion 操作

1. 打开 Git Log（`Alt+9` 或菜单 Git → Log）
2. 右键已知"好"的 commit → **Mark as Good**
3. 右键已知"坏"的 commit（通常是 HEAD）→ **Mark as Bad**
4. CLion 自动 checkout 中间版本
5. 编译测试，根据结果点击 **Good** 或 **Bad**
6. 重复直到 CLion 提示"First bad commit found"

### 命令行操作

```bash
# 开始二分
git bisect start

# 标记当前 HEAD 为坏（测试失败）
git bisect bad

# 标记已知正常的 commit 为好（初始提交肯定没有 bug）
git bisect good f2e0c3a    # 第一个 commit 的 hash

# Git 自动 checkout 中间版本，编译并测试
g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test
# 如果输出 "SOME FAIL" → git bisect bad
# 如果输出 "ALL PASS"  → git bisect good

# 重复几次后 Git 输出：
# 3d8b2f0 is the first bad commit
# commit 3d8b2f0...
# refactor: simplify variance denominator

# 退出二分，恢复 HEAD
git bisect reset
```

### 自动化 bisect

```bash
# 提供一个测试脚本，Git 全自动完成二分
git bisect start HEAD f2e0c3a
git bisect run bash -c "g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test"
```

返回值 0 表示 good，非 0 表示 bad，完全自动化。

---

## 3.3 git revert：安全撤销已发布 commit

### 概念

`revert` 生成一个"反向 commit"，内容是撤销指定 commit 的改动。**不改变历史**，适合已经 push 到共享分支的情况。

与 `reset --hard` 的区别：

| | revert | reset --hard |
|---|---|---|
| 历史 | 保留，追加新 commit | 删除，历史被重写 |
| 已推送分支 | 安全 | 危险，需要 force push |
| 适用场景 | 生产分支、共享分支 | 本地未推送的临时清理 |

### CLion 操作

1. Git → Log，找到要撤销的 commit
2. 右键 → **Revert Commit**
3. CLion 自动创建反向 commit（可能需要处理冲突）

### 命令行操作

```bash
# 撤销单个 commit
git revert 3d8b2f0

# 撤销连续多个 commit（不包含起点）
git revert a1c4e22..HEAD

# 仅生成改动，不自动提交（手动检查后再 commit）
git revert --no-commit 3d8b2f0
git status    # 查看改动
git commit -m "revert: undo variance denominator change"
```

### 练习

```bash
cd practice_repo
# 确认当前测试失败
g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test   # SOME FAIL

# 用 revert 撤销 bug commit
git log --oneline   # 找到 "refactor: simplify variance denominator" 的 hash
git revert <hash>

# 再次测试
g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test   # ALL PASS
git log --oneline   # 观察新增了一个 Revert commit
```

---

## 3.4 git cherry-pick：摘取指定 commit

### 概念

`cherry-pick` 把另一个分支上的某个 commit"复制"到当前分支，生成内容相同但 hash 不同的新 commit。

**典型场景：**
- `fix/variance-denominator` 分支有修复，`main` 还没有 → cherry-pick 那个修复
- 紧急 bugfix 先合入 `release` 分支，再 cherry-pick 到 `develop`

### CLion 操作

1. Git → Log，在分支下拉中选择或搜索目标分支
2. 找到要摘取的 commit，右键 → **Cherry-Pick**
3. 如有冲突，CLion 弹出 3-way merge 编辑器

**3-way merge 编辑器说明：**
- 左：当前分支版本（yours）
- 中：合并结果（手动编辑这一列）
- 右：被摘取 commit 的版本（theirs）
- 点击 `>>` / `<<` 按钮选择接受哪侧改动

### 命令行操作

```bash
# 摘取单个 commit
git cherry-pick <hash>

# 摘取连续范围（不含起点）
git cherry-pick <start-hash>..<end-hash>

# 摘取但不自动 commit（检查后手动提交）
git cherry-pick --no-commit <hash>

# 遇到冲突后：手动解决冲突文件，然后
git add calc.cpp
git cherry-pick --continue
# 或放弃
git cherry-pick --abort
```

### 练习

```bash
cd practice_repo
# 先 reset 让 main 处于有 bug 状态（如果之前做了 revert 先撤销它）
git log --oneline fix/variance-denominator  # 找到 "fix: revert variance" 的 hash

git cherry-pick <hash>
g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test   # ALL PASS
git log --oneline   # 观察 cherry-pick 生成的新 commit
```

---

## 3.5 git worktree：多工作区并行

### 概念

`worktree` 让同一个 Git 仓库在多个目录同时 checkout 不同分支，共享 `.git` 目录。

**对比 clone：**
- clone 需要重新下载对象，worktree 共享同一个对象库，瞬间创建
- clone 的两个仓库相互独立，worktree 的分支状态共享

**典型场景：**
- 当前在 `feature/new-planner` 开发，生产出了 bug 需要在 `main` 上修复，不想 stash 打断当前工作
- 在 worktree 中修复 bug，回来继续开发，完全隔离

### 命令行操作

```bash
# 在 ../hotfix_verify 目录创建 worktree，checkout fix/variance-denominator 分支
git worktree add ../hotfix_verify fix/variance-denominator

# 查看所有 worktree
git worktree list

# 进入新 worktree
cd ../hotfix_verify
git branch   # 显示当前在 fix/variance-denominator
g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test   # 验证修复

# 回到主目录，两个目录同时存在
cd ../practice_repo

# 删除 worktree（先退出该目录）
git worktree remove ../hotfix_verify
```

### CLion 使用 worktree

CLion 没有内置 worktree 管理 UI，但每个 worktree 目录可以直接作为独立项目打开：
1. `git worktree add ../hotfix_verify fix/variance-denominator`
2. CLion → File → Open → 选择 `../hotfix_verify`
3. 两个 CLion 窗口分别对应两个分支，互不干扰

---

## 3.6 补充：git stash

快速暂存当前未提交改动，切换分支后恢复。

**CLion 操作：** Git → Uncommitted Changes → Shelve Changes（CLion 版 stash，支持命名和管理）

```bash
git stash push -m "wip: new planner"   # 暂存并命名
git stash list                          # 查看所有暂存
git stash pop                           # 恢复最新暂存并删除
git stash apply stash@{1}              # 恢复指定暂存但不删除
git stash drop stash@{0}               # 删除指定暂存
```

---

## 3.7 补充：git reflog

`reflog` 记录 HEAD 的每一次移动，是误操作后的"后悔药"。

```bash
git reflog                     # 查看 HEAD 移动历史
# 输出类似：
# e5f3a1c HEAD@{0}: cherry-pick: fix: revert variance
# 3d8b2f0 HEAD@{1}: reset: moving to HEAD~1
# ...

git checkout HEAD@{2}          # 恢复到任意历史状态
git branch recovery HEAD@{2}   # 从历史状态创建新分支（恢复误删分支）
```

---

## 练习流程总结

```bash
cd ch3_git_advanced
./setup_repo.sh
cd practice_repo

# 1. bisect 定位 bug
git bisect start
git bisect bad
git bisect good HEAD~4
# 按提示编译测试，标记 good/bad，找到 bug commit

# 2. revert 安全撤销
git bisect reset
git revert <bug-commit-hash>
g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test

# 3. worktree 在 fix 分支上独立验证
git worktree add ../verify fix/variance-denominator
cd ../verify && g++ -std=c++17 calc.cpp test_calc.cpp -o test && ./test
cd ../practice_repo

# 4. cherry-pick 摘取 fix 分支的修复到 main
git log --oneline fix/variance-denominator
git cherry-pick <fix-commit-hash>
git log --oneline   # 查看完整历史
```
