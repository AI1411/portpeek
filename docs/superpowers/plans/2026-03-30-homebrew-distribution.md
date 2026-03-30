# Homebrew Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `brew tap AI1411/tap && brew install pps` でインストールできるようにする。

**Architecture:** GitHub Actions の `release.yml` が `v*` タグで起動し、macOS arm64 / x86_64 バイナリをビルドして GitHub Release を作成し、`AI1411/homebrew-tap` の formula を自動更新する。

**Tech Stack:** GitHub Actions、Zig 0.15.2、Homebrew formula (Ruby)、`gh` CLI、`mlugg/setup-zig@v2`

---

## ファイル構成

| ファイル | リポジトリ | 責務 |
|---------|-----------|------|
| `.github/workflows/release.yml` | `AI1411/portpeek` | ビルド・リリース・tap 更新の自動化 |
| `Formula/pps.rb` | `AI1411/homebrew-tap`（新規作成） | brew install 定義（URL・SHA256・install 手順） |

---

## Task 1: homebrew-tap リポジトリの作成と初期 formula の追加

**前提:** GitHub にログイン済みの `gh` CLI が使えること。

**Files:**
- Create: `Formula/pps.rb` in `AI1411/homebrew-tap` repo (このリポジトリの外)

- [ ] **Step 1: `AI1411/homebrew-tap` リポジトリを作成する**

```bash
gh repo create AI1411/homebrew-tap --public --description "Homebrew tap for AI1411 tools"
```

期待: `https://github.com/AI1411/homebrew-tap` が作成される

- [ ] **Step 2: ローカルにクローンする**

```bash
cd /tmp
git clone https://github.com/AI1411/homebrew-tap.git
cd homebrew-tap
mkdir Formula
```

- [ ] **Step 3: `Formula/pps.rb` を作成する**

```ruby
class Pps < Formula
  desc "Interactive port snapshot and kill tool"
  homepage "https://github.com/AI1411/portpeek"
  version "0.0.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/portpeek/releases/download/v#{version}/pps-aarch64-macos.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # aarch64
    else
      url "https://github.com/AI1411/portpeek/releases/download/v#{version}/pps-x86_64-macos.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000" # x86_64
    end
  end

  def install
    bin.install "pps"
  end
end
```

- [ ] **Step 4: コミットしてプッシュする**

```bash
git add Formula/pps.rb
git commit -m "feat: add pps formula"
git push origin main
```

期待: `https://github.com/AI1411/homebrew-tap/blob/main/Formula/pps.rb` が見える

---

## Task 2: HOMEBREW_TAP_TOKEN secret の登録

**Files:** なし（GitHub UI / `gh` CLI での操作）

- [ ] **Step 1: Personal Access Token を作成する**

GitHub.com → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token

スコープ: `repo` にチェックを入れる（`AI1411/homebrew-tap` への書き込みに必要）

名前: `HOMEBREW_TAP_TOKEN`

生成されたトークンをコピーしておく（この画面を離れると二度と見られない）

- [ ] **Step 2: portpeek リポジトリに secret を登録する**

```bash
# portpeek のディレクトリに移動して実行
cd /Users/ishiiakira/dev/portsnap
gh secret set HOMEBREW_TAP_TOKEN --repo AI1411/portpeek
```

プロンプトにコピーしたトークンを貼り付けて Enter

期待:
```
✓ Set Actions secret HOMEBREW_TAP_TOKEN for AI1411/portpeek
```

---

## Task 3: release.yml の作成

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: `.github/workflows/` ディレクトリを作成して `release.yml` を作成する**

```bash
mkdir -p /Users/ishiiakira/dev/portsnap/.github/workflows
```

ファイルの内容:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

permissions:
  contents: write

jobs:
  build:
    name: Build ${{ matrix.target }}
    runs-on: macos-latest
    strategy:
      matrix:
        target:
          - aarch64-macos
          - x86_64-macos
    steps:
      - uses: actions/checkout@v4

      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.0

      - name: Build binary
        run: |
          zig build -Dtarget=${{ matrix.target }} -Doptimize=ReleaseFast
          mkdir dist
          cp zig-out/bin/pps dist/pps
          cd dist
          tar czf pps-${{ matrix.target }}.tar.gz pps

      - uses: actions/upload-artifact@v4
        with:
          name: pps-${{ matrix.target }}
          path: dist/pps-${{ matrix.target }}.tar.gz

  release:
    needs: build
    runs-on: ubuntu-latest
    outputs:
      aarch64_sha256: ${{ steps.sha.outputs.aarch64_sha256 }}
      x86_64_sha256: ${{ steps.sha.outputs.x86_64_sha256 }}
    steps:
      - uses: actions/download-artifact@v4
        with:
          pattern: pps-*
          merge-multiple: true

      - name: Compute SHA256
        id: sha
        run: |
          echo "aarch64_sha256=$(sha256sum pps-aarch64-macos.tar.gz | cut -d' ' -f1)" >> $GITHUB_OUTPUT
          echo "x86_64_sha256=$(sha256sum pps-x86_64-macos.tar.gz | cut -d' ' -f1)" >> $GITHUB_OUTPUT

      - name: Create GitHub Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create ${{ github.ref_name }} \
            pps-aarch64-macos.tar.gz \
            pps-x86_64-macos.tar.gz \
            --repo ${{ github.repository }} \
            --title "${{ github.ref_name }}" \
            --generate-notes

  update-tap:
    needs: release
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          repository: AI1411/homebrew-tap
          token: ${{ secrets.HOMEBREW_TAP_TOKEN }}

      - name: Update formula
        env:
          VERSION: ${{ github.ref_name }}
          AARCH64_SHA256: ${{ needs.release.outputs.aarch64_sha256 }}
          X86_64_SHA256: ${{ needs.release.outputs.x86_64_sha256 }}
        run: |
          VERSION_NUM=${VERSION#v}
          sed -i "s/version \".*\"/version \"${VERSION_NUM}\"/" Formula/pps.rb
          sed -i "s/sha256 \"[0-9a-f]*\" # aarch64/sha256 \"${AARCH64_SHA256}\" # aarch64/" Formula/pps.rb
          sed -i "s/sha256 \"[0-9a-f]*\" # x86_64/sha256 \"${X86_64_SHA256}\" # x86_64/" Formula/pps.rb

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Formula/pps.rb
          git commit -m "chore: update pps to ${{ github.ref_name }}"
          git push
```

- [ ] **Step 2: コミットする**

```bash
cd /Users/ishiiakira/dev/portsnap
git add .github/workflows/release.yml
git commit -m "ci: add release workflow for Homebrew distribution"
git push
```

---

## Task 4: 動作確認（タグを切ってリリースを確認する）

- [ ] **Step 1: 現在の main ブランチが最新であることを確認する**

```bash
git checkout main
git pull origin main
```

- [ ] **Step 2: `v0.1.0` タグを切ってプッシュする**

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 3: Actions の実行状況を確認する**

```bash
gh run watch --repo AI1411/portpeek
```

期待: `build (aarch64-macos)` → `build (x86_64-macos)` → `release` → `update-tap` の順に成功

- [ ] **Step 4: GitHub Release が作成されたことを確認する**

```bash
gh release view v0.1.0 --repo AI1411/portpeek
```

期待: `pps-aarch64-macos.tar.gz` と `pps-x86_64-macos.tar.gz` がアセットに含まれている

- [ ] **Step 5: homebrew-tap の formula が更新されたことを確認する**

```bash
gh api repos/AI1411/homebrew-tap/contents/Formula/pps.rb \
  --jq '.content' | base64 -d | grep -E 'version|sha256'
```

期待:
```
  version "0.1.0"
      sha256 "<実際のハッシュ値>" # aarch64
      sha256 "<実際のハッシュ値>" # x86_64
```

- [ ] **Step 6: `brew install` を試す**

```bash
brew tap AI1411/tap
brew install pps
pps --json | head -5
```

期待: JSON 形式でポート一覧が出力される

- [ ] **Step 7: README にインストール方法を追記してコミットする**

`README.md` の「インストール」セクションを以下に更新:

```markdown
## インストール

### Homebrew（macOS）

```bash
brew tap AI1411/tap
brew install pps
```

### ソースからビルド

```bash
git clone https://github.com/AI1411/portpeek.git
cd portpeek
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/pps /usr/local/bin/
```

**要件:** Zig 0.15+
```

```bash
git add README.md
git commit -m "docs: add Homebrew install instructions"
git push
```

---

## トラブルシューティング

### `mlugg/setup-zig` で 0.15.0 が見つからない場合

`release.yml` の `version` を `0.15.2` または `master` に変更する:

```yaml
      - uses: mlugg/setup-zig@v2
        with:
          version: 0.15.2
```

### `update-tap` ジョブが権限エラーになる場合

`HOMEBREW_TAP_TOKEN` の PAT が `repo` スコープを持っていることを確認する。
Fine-grained token を使う場合は `AI1411/homebrew-tap` への `Contents: Write` 権限が必要。

### `sed` の置換が効かない場合

formula ファイルの sha256 行に `# aarch64` / `# x86_64` コメントが正確に含まれていることを確認する。
