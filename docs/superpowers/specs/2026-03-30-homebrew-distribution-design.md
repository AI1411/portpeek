# Homebrew Distribution — Design Spec

**Date:** 2026-03-30
**Status:** Approved

---

## 概要

`pps` を `brew install` でインストールできるようにする。
`AI1411/homebrew-tap` リポジトリを作成し、GitHub Actions でタグプッシュ時に自動ビルド・リリース・formula 更新まで行う。

---

## アーキテクチャ

### 構成要素

| コンポーネント | 場所 | 責務 |
|---|---|---|
| Release workflow | `portpeek/.github/workflows/release.yml` | タグ検知 → バイナリビルド → Release 作成 → tap 更新 |
| Homebrew formula | `AI1411/homebrew-tap/Formula/pps.rb` | brew install の定義（URL・SHA256・install 手順） |
| PAT secret | portpeek リポジトリの Actions secret | workflow から tap repo への書き込み権限 |

### 対応プラットフォーム

- macOS arm64 (`aarch64-macos`)
- macOS x86_64 (`x86_64-macos`)

---

## リリースフロー

```
開発者: git tag v1.0.0 && git push origin v1.0.0
              ↓
GitHub Actions (release.yml) 起動
              ↓
  [job: build-macos]
  zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast
  → pps-aarch64-macos.tar.gz + SHA256
  zig build -Dtarget=x86_64-macos  -Doptimize=ReleaseFast
  → pps-x86_64-macos.tar.gz  + SHA256
              ↓
  [job: release]
  gh release create v1.0.0 *.tar.gz
              ↓
  [job: update-tap]
  homebrew-tap の Formula/pps.rb を
  新バージョン・新 SHA256 で更新してコミット
```

---

## ファイル詳細

### `.github/workflows/release.yml`

```yaml
on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: macos-latest
    strategy:
      matrix:
        target: [aarch64-macos, x86_64-macos]
    steps:
      - checkout
      - install zig
      - zig build -Dtarget=${{ matrix.target }} -Doptimize=ReleaseFast
      - tar + sha256sum
      - upload artifact

  release:
    needs: build
    steps:
      - download artifacts
      - gh release create ${{ github.ref_name }} *.tar.gz

  update-tap:
    needs: release
    steps:
      - checkout AI1411/homebrew-tap (using HOMEBREW_TAP_TOKEN)
      - sed で version / sha256 を書き換え
      - git commit & push
```

### `Formula/pps.rb`（homebrew-tap）

```ruby
class Pps < Formula
  desc "Interactive port snapshot and kill tool"
  homepage "https://github.com/AI1411/portpeek"
  version "1.0.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/AI1411/portpeek/releases/download/v#{version}/pps-aarch64-macos.tar.gz"
      sha256 "<aarch64-sha256>"
    else
      url "https://github.com/AI1411/portpeek/releases/download/v#{version}/pps-x86_64-macos.tar.gz"
      sha256 "<x86_64-sha256>"
    end
  end

  def install
    bin.install "pps"
  end
end
```

---

## ユーザー操作

### 初回インストール

```bash
brew tap AI1411/tap
brew install pps
```

### アップグレード

```bash
brew upgrade pps
```

---

## 前提作業（手動）

以下は一度だけ人手で行う初期設定:

1. `AI1411/homebrew-tap` リポジトリを GitHub 上で作成（Public）
2. `Formula/pps.rb` の初期ファイルをそのリポジトリに追加
3. portpeek リポジトリの Actions secrets に `HOMEBREW_TAP_TOKEN` を登録
   - GitHub の Personal Access Token（`repo` スコープ）を使用

---

## エラーハンドリング

| ケース | 対応 |
|--------|------|
| ビルド失敗 | job が fail → Release は作成されない |
| tap 更新失敗 | Release は作成済みのため、手動で formula を更新する |
| 既存タグへの再プッシュ | `gh release create` が失敗する（冪等性なし）—— 同タグは使い回さない |

---

## 対象外

- Linux バイナリ配布（今回スコープ外）
- homebrew-core への公式登録
- `brew test` / audit 対応
