# portsnap — 設計ドキュメント

## コンセプト

Zig製の超高速ポート使用状況ビューア。`/proc/net/tcp` を直接パースし、どのプロセスがどのポートを掴んでいるかを瞬時に一覧表示する。ポート衝突の検出、プロセスの即キル、ポート待ち受け（特定ポートが空くまでブロック）を1バイナリで実現。

### 既存ツールとの差別化

| ツール | 問題点 | portsnap の優位性 |
|--------|--------|-------------------|
| lsof -i | 遅い（数百ms〜数秒）、出力が読みにくい | /proc直読みで <10ms、カラー表示 |
| netstat | 非推奨、プロセス名が出ない場合あり | PID→コマンド名を自動解決 |
| ss | 高速だが出力フォーマットが扱いにくい | 構造化出力 + フィルタ + アクション |
| fuser | 単一ポートのみ | 全ポート一覧 + 選択的操作 |

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│                  CLI Entry                      │
│  portsnap [command] [options]                   │
└──────────────┬──────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────┐
│            Port Scanner                         │
│                                                 │
│  /proc/net/tcp   ──┐                            │
│  /proc/net/tcp6  ──┤── Parse & Merge            │
│  /proc/net/udp   ──┤                            │
│  /proc/net/udp6  ──┘                            │
│                                                 │
│  inode → PID マッピング                          │
│  (/proc/[pid]/fd/ のシンボリックリンク走査)       │
│                                                 │
│  PID → プロセス情報                              │
│  (/proc/[pid]/comm, /proc/[pid]/cmdline)        │
└──────────────┬──────────────────────────────────┘
               │
       ┌───────┼───────┐
       ▼       ▼       ▼
┌──────────┐ ┌─────┐ ┌──────────┐
│ List     │ │Kill │ │ Watch    │
│ (stdout/ │ │     │ │ (poll    │
│  TUI)    │ │     │ │  loop)   │
└──────────┘ └─────┘ └──────────┘
```

### パフォーマンス設計

1. **mmap で /proc/net/tcp を読む**: read() より高速、カーネルバッファを直接参照
2. **inode→PID の逆引きキャッシュ**: /proc/[pid]/fd をスキャンして HashMap に格納。2回目以降はキャッシュヒット
3. **Arena Allocator**: スキャン1回分のメモリを一括確保→一括解放。GCなしで断片化ゼロ

---

## CLI インターフェース

```bash
# 基本: 全ポート一覧
portsnap

# 出力例:
#  PROTO  LOCAL            REMOTE           STATE        PID    PROCESS     CMD
#  tcp    127.0.0.1:5432   0.0.0.0:*        LISTEN       1234   postgres    /usr/lib/postgresql/16/bin/postgres
#  tcp    0.0.0.0:8080     0.0.0.0:*        LISTEN       5678   main        ./my-api-server --port 8080
#  tcp    0.0.0.0:3000     0.0.0.0:*        LISTEN       9012   node        node .next/standalone/server.js
#  tcp    127.0.0.1:6379   0.0.0.0:*        LISTEN       3456   redis-ser   redis-server *:6379
#  udp    0.0.0.0:53       0.0.0.0:*                     7890   dnsmasq     /usr/sbin/dnsmasq

# ポート番号でフィルタ
portsnap :8080
portsnap :3000-9000

# プロセス名でフィルタ
portsnap -p node
portsnap -p "go|rust"

# LISTENのみ表示
portsnap -l

# ポートを使っているプロセスをキル
portsnap kill :8080
portsnap kill :3000 --signal SIGTERM   # デフォルト
portsnap kill :3000 --signal SIGKILL   # 強制

# ポートが空くまで待つ（タイムアウト付き）
portsnap wait :8080 --timeout 30s
# → ポートが解放された瞬間に exit 0
# → タイムアウトで exit 1

# ポート使用状況をリアルタイム監視 (TUI)
portsnap watch

# JSON出力 (スクリプト連携用)
portsnap --json
portsnap --json | jq '.[] | select(.port == 8080)'

# 衝突検知: 同一ポートに複数プロセスがバインドしようとしてないか
portsnap check 8080 3000 5432
# → 使用中なら exit 1 + 詳細表示
# → 空きなら exit 0

# docker コンテナのポートマッピングも表示
portsnap --docker
```

---

## 出力フォーマット

### カラー付きテーブル (デフォルト)

```
portsnap — 12 ports in use

 PROTO  LOCAL              STATE     PID    PROCESS       COMMAND
 ───────────────────────────────────────────────────────────────────
 tcp    0.0.0.0:3000       LISTEN    9012   node          next start
 tcp    0.0.0.0:8080       LISTEN    5678   my-api        ./my-api --port 8080
 tcp    127.0.0.1:5432     LISTEN    1234   postgres      postgres -D /data
 tcp    127.0.0.1:6379     LISTEN    3456   redis-ser     redis-server *:6379
 tcp    0.0.0.0:9090       LISTEN    7777   prometheus    prometheus --config...
 udp    0.0.0.0:53                   7890   dnsmasq       dnsmasq --no-resolv

 ───────────────────────────────────────────────────────────────────
 tcp    192.168.1.5:8080   ESTABL    5678   my-api        → 10.0.0.3:52431
 tcp    192.168.1.5:8080   ESTABL    5678   my-api        → 10.0.0.3:52432
 tcp    192.168.1.5:5432   ESTABL    1234   postgres      → 127.0.0.1:41200
 ...

色分け:
  - LISTEN:       緑
  - ESTABLISHED:  青
  - TIME_WAIT:    灰色
  - CLOSE_WAIT:   黄色 (リーク候補)
  - 高ポート番号:  暗め表示
```

### JSON 出力

```json
[
  {
    "protocol": "tcp",
    "local_addr": "0.0.0.0",
    "local_port": 8080,
    "remote_addr": "0.0.0.0",
    "remote_port": 0,
    "state": "LISTEN",
    "pid": 5678,
    "process": "my-api",
    "cmdline": "./my-api-server --port 8080",
    "uid": 1000,
    "inode": 123456
  }
]
```

---

## watch モード (TUI)

```
┌─ portsnap watch ──────────────────────────────────────────────┐
│  Monitoring 14 ports    Refresh: 1.0s    Filter: LISTEN       │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  PORT   PROTO  PROCESS       PID    CONNS  STATE              │
│  ─────────────────────────────────────────────────────────    │
│  3000   tcp    node          9012   0      LISTEN              │
│  5432   tcp    postgres      1234   3      LISTEN (+3 EST)     │
│  6379   tcp    redis-ser     3456   12     LISTEN (+12 EST)    │
│  8080   tcp    my-api        5678   47     LISTEN (+47 EST)    │
│  9090   tcp    prometheus    7777   2      LISTEN (+2 EST)     │
│                                                               │
│  ── Recent Changes ──────────────────────────────────────     │
│  [15:30:12] + :4000 node (PID 11234) started listening        │
│  [15:30:08] - :4000 node (PID 10500) stopped                  │
│  [15:29:55] ! :8080 connections spike: 47 → 128               │
│                                                               │
├───────────────────────────────────────────────────────────────┤
│ [q] 終了  [k] 選択プロセスをkill  [f] フィルタ  [j/k] 移動   │
└───────────────────────────────────────────────────────────────┘
```

---

## /proc パース仕様

### /proc/net/tcp のフォーマット

```
  sl  local_address rem_address   st tx_queue rx_queue tr ...  inode
   0: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:... 12345
```

- `local_address`: hex エンコードされた IP:Port (リトルエンディアン)
- `rem_address`: 同上
- `st`: ソケット状態 (0A = LISTEN, 01 = ESTABLISHED, ...)
- `inode`: ソケットの inode 番号

### inode → PID マッピング

```
/proc/[pid]/fd/ 以下のシンボリックリンクを走査
  /proc/5678/fd/3 → socket:[12345]
                             ^^^^^ inode番号
```

### PID → プロセス情報

```
/proc/[pid]/comm     → プロセス名 (最大16文字)
/proc/[pid]/cmdline  → フルコマンドライン (NULL区切り)
/proc/[pid]/status   → UID, GID 等
```

---

## プロジェクト構成

```
portsnap/
├── build.zig
├── build.zig.zon
├── README.md
│
├── src/
│   ├── main.zig              # CLI エントリ、引数パース
│   │
│   ├── scanner/
│   │   ├── proc_net.zig      # /proc/net/tcp,udp パーサー
│   │   ├── proc_fd.zig       # inode → PID 逆引き
│   │   ├── proc_info.zig     # PID → プロセス情報
│   │   ├── docker.zig        # Docker API (unix socket) 連携
│   │   └── types.zig         # PortEntry, ProcessInfo 等
│   │
│   ├── filter/
│   │   ├── port.zig          # ポート番号/範囲フィルタ
│   │   ├── process.zig       # プロセス名フィルタ (regex)
│   │   └── state.zig         # ソケット状態フィルタ
│   │
│   ├── action/
│   │   ├── kill.zig          # プロセスキル (SIGTERM/SIGKILL)
│   │   ├── wait.zig          # ポート解放待ち (poll)
│   │   └── check.zig         # ポート空きチェック
│   │
│   ├── output/
│   │   ├── table.zig         # カラー付きテーブル表示
│   │   ├── json.zig          # JSON 出力
│   │   └── tui.zig           # watch モード TUI
│   │
│   └── utils/
│       ├── hex.zig           # hex IP/Port デコーダー
│       ├── color.zig         # ANSI カラーヘルパー
│       └── signal.zig        # シグナル送信ラッパー
│
└── tests/
    ├── proc_net_test.zig     # パーサーユニットテスト
    └── fixtures/
        ├── tcp_sample.txt    # テスト用 /proc/net/tcp ダミー
        └── tcp6_sample.txt
```

---

## 実装フェーズ

### Phase 1: コアスキャナー (Week 1)

```
目標: portsnap で全LISTENポートが一覧表示される

タスク:
  [1] /proc/net/tcp パーサー (hex IP/Port デコード)
  [2] /proc/net/tcp6 対応 (IPv6)
  [3] inode → PID マッピング (/proc/[pid]/fd 走査)
  [4] PID → プロセス名解決 (/proc/[pid]/comm)
  [5] カラー付きテーブル出力
  [6] LISTEN/ESTABLISHED の状態色分け
```

### Phase 2: フィルタ＆アクション (Week 2)

```
目標: portsnap :8080, portsnap kill :3000, portsnap wait :8080 が動く

タスク:
  [1] ポート番号フィルタ (単一, 範囲, カンマ区切り)
  [2] プロセス名フィルタ (-p オプション)
  [3] 状態フィルタ (-l で LISTEN のみ)
  [4] kill サブコマンド (SIGTERM/SIGKILL)
  [5] wait サブコマンド (poll + タイムアウト)
  [6] check サブコマンド (終了コード制御)
  [7] JSON 出力 (--json)
```

### Phase 3: watch モード＆Docker連携 (Week 3)

```
目標: portsnap watch でリアルタイムTUI、--docker でコンテナ情報表示

タスク:
  [1] watch モード TUI (1秒間隔でリフレッシュ)
  [2] 変更検出 (新規LISTEN, 解放, コネクション急増)
  [3] TUI内キル操作 (k キー)
  [4] Docker unix socket API 連携 (ポートマッピング取得)
  [5] UDP 対応 (/proc/net/udp, udp6)
  [6] cmdline フル表示 (--full オプション)
```

---

## Zig の特性が活きるポイント

### 1. /proc 直読みでシステムコールを最小化

```zig
// mmap で /proc/net/tcp を読む — コピーなしで直接パース
const file = try std.fs.openFileAbsolute("/proc/net/tcp", .{});
defer file.close();
const content = try file.readToEndAlloc(arena.allocator(), 1024 * 1024);
// arena で一括管理、スキャン完了後に全解放
```

### 2. comptime で hex デコードを最適化

```zig
// /proc/net/tcp の hex IP アドレスをコンパイル時テーブルでデコード
const hex_table = comptime blk: {
    var table: [256]u8 = undefined;
    for (0..256) |i| {
        table[i] = switch (i) {
            '0'...'9' => |c| c - '0',
            'A'...'F' => |c| c - 'A' + 10,
            'a'...'f' => |c| c - 'a' + 10,
            else => 0xFF,
        };
    };
    break :blk table;
};
```

### 3. ゼロアロケーション・ラインパーサー

```zig
// /proc/net/tcp の各行をアロケーションなしでパース
fn parseLine(line: []const u8) ?PortEntry {
    // 固定オフセットでスライス — malloc 不要
    const local_hex = line[6..14];
    const local_port_hex = line[15..19];
    const state_hex = line[...];
    // すべてスタック上で完結
}
```

---

## 成功指標

1. **速度**: `portsnap` の実行が `lsof -i` の 10倍以上速い (< 5ms vs 50-500ms)
2. **バイナリサイズ**: < 500KB
3. **依存**: ゼロ (libc すら不要、static linked)
4. **対応**: Linux (primary)、macOS (Phase 4 で /proc 代替)