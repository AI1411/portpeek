# pps

ポートスナップショットツール。使用中のポートとプロセスをインタラクティブに確認・killできます。

## 特徴

- **インタラクティブ選択モード** — TTY で起動するとカーソル操作でポートを選択し、Enter で確認後に SIGTERM を送信
- **macOS / Linux 対応** — macOS は `lsof`、Linux は `/proc/net` を使用
- **JSON 出力** — `--json` でスクリプト連携に対応
- **サブコマンド** — `kill`、`wait`、`check`、`watch` でポート管理を自動化
- **Docker 対応** — `--docker` でコンテナのポートマッピングも表示

## インストール

### Homebrew（macOS 推奨）

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

## 使い方

### インタラクティブモード（デフォルト）

```bash
pps
```

| キー | 動作 |
|------|------|
| `↑` / `k` | 1行上に移動 |
| `↓` / `j` | 1行下に移動 |
| `Enter` | kill確認プロンプト |
| `y` | SIGTERM 送信して終了 |
| `n` / `Esc` | プロンプトをキャンセル |
| `q` | 終了 |

### フィルタオプション

```bash
pps -l               # LISTEN 状態のみ表示
pps :8080            # ポート番号で絞り込み
pps -p nginx         # プロセス名で絞り込み
pps -l --docker      # LISTEN + Docker ポートマッピング
```

### 非インタラクティブ出力

```bash
pps --json           # JSON 出力
pps | grep 8080      # パイプ時はテーブル出力
```

### サブコマンド

```bash
# 指定ポートのプロセスを kill する
pps kill :8080
pps kill :8080 --signal SIGKILL

# ポートが空くまで待機する
pps wait :8080
pps wait :8080 --timeout 60s

# ポートの使用状況をチェックする（CI 向け）
pps check :8080 :5432 :6379

# 1秒ごとにポート一覧を更新して表示する（TUI watch モード）
pps watch
```

## 出力例

```
pps — 3 ports  [↑↓/jk] 移動  [Enter] kill  [q] 終了

  PROTO  PORT             STATE         PID      PROCESS
─────────────────────────────────────────────────────────
  tcp    8080             LISTEN        1234     nginx
> tcp    3000             LISTEN        5678     node
  tcp    5432             LISTEN        9012     postgres
```

## ビルドとテスト

```bash
zig build               # ビルド
zig build test          # ユニットテスト実行
zig build run           # 直接実行
```

## 対応 OS

| OS | スキャン方法 |
|----|------------|
| Linux | `/proc/net/tcp`, `/proc/net/udp` |
| macOS | `lsof -i -n -P` |
