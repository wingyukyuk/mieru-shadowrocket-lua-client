# mieru-shadowrocket-lua-client

> 以純 Lua 腳本實現的 [mieru](https://github.com/enfein/mieru) 代理協議客戶端，供 [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) 使用（概念驗證）

**For English, please refer to [README.md](README.md)**

## 簡介

本專案是一個概念驗證（Proof of Concept）的 mieru 代理協議客戶端，以純 Lua 腳本實現，可作為 [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) 的 Lua 後端使用。

腳本完整實現了 mieru v3 協議的 TCP 模式，包括：

- **XChaCha20-Poly1305** AEAD 加解密
- **Poly1305** 訊息驗證碼
- **ChaCha20** 串流加密
- **SHA-256** 雜湊函數
- **HMAC-SHA256** 與 **PBKDF2-SHA256** 金鑰衍生
- SOCKS5 連線請求封裝
- 隱式 nonce 遞增機制
- 會話（Session）管理與分段（Segment）協議處理

## ⚠️ 特別提醒

1. **若 Shadowrocket 未來原生支援 mieru 協議，請退回使用官方內建組件。** 原生組件的效能與穩定性遠優於 Lua 腳本實現。
2. 此腳本使用 AI 輔助編寫，並經人工驗證。
3. 目前**僅支援 TCP 模式下的 v3 協議版本**。
4. 由於 Shadowrocket 的 Lua 環境未暴露所需的加密演算法原生介面，所有加解密運算均以純 Lua 腳本執行，**效率非常低下**。在 iPhone 系列裝置上，預計僅能達到約 **0.5–1 Mbps** 的上下載速度。

## 使用方法

### 前置條件

- 已安裝 [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118)
- 已部署可用的 mieru 伺服器端（v3 協議，TCP 模式）

### 設定步驟

1. 將 `mieru-backend-allinone.lua` 檔案透過任意方式傳輸至 iOS 裝置（例如 iCloud、AirDrop、網頁伺服器等）。

2. 開啟 Shadowrocket，新增節點，類型選擇 **Lua**。

3. 填寫以下欄位：

   | 欄位 | 說明 |
   |------|------|
   | **地址（Address）** | mieru 伺服器地址 |
   | **連接埠（Port）** | mieru 伺服器連接埠 |
   | **使用者（User）** | mieru 帳號的使用者名稱 |
   | **密碼（Password）** | mieru 帳號的密碼 |
   | **檔案（File）** | 選擇 `mieru-backend-allinone.lua` 檔案 |

4. 其他選項在腳本中未使用，請保留預設值。

5. 儲存節點後即可連線使用。

### 進階設定（選填）

腳本支援透過 Shadowrocket 的 `settings` 物件傳入以下額外參數：

| 參數名稱 | 說明 | 預設值 |
|----------|------|--------|
| `protocol_version` | 協議版本（目前僅支援 `v3`） | `v3` |
| `time_offset_sec` | 時間偏移量（秒），用於修正客戶端與伺服器的時鐘差異 | `0` |
| `debug` | 啟用除錯日誌（`true` / `false`） | `false` |

## 疑難排解

若連線失敗或卡住，可使用診斷版本進行排查：

1. 在 Shadowrocket 節點設定中，將腳本檔案從 `mieru-backend-allinone.lua` 切換為 `mieru-backend-diagnostic-allinone.lua`。
2. 保持 `protocol_version` 為 `v3`（預設值）。
3. 重新嘗試一次失敗的請求。
4. 匯出或檢視 Shadowrocket 日誌，尋找包含 `[mieru-diag]` 的行。

### 常見問題

**交握完成後遠端伺服器立即關閉連線：**

這通常表示裝置與伺服器之間存在時鐘偏差。請嘗試將 `time_offset_sec` 設定為 `120` 或 `-120` 後再測試。

**速度非常慢：**

- 請確認使用的是 `mieru-backend-allinone.lua`（而非診斷版本）。
- 將 `debug` 設為 `false`（或不設定）。
- 診斷版本與除錯日誌會在 iOS 上產生顯著的額外開銷。

## 開發指南

### 檔案結構

| 檔案 | 說明 |
|------|------|
| `mieru-core.lua` | 協議核心——所有加解密演算法、金鑰管理、會話與分段協議處理 |
| `mieru-backend.lua` | Shadowrocket Lua 後端適配器——實現 `wa_lua_on_*` 回呼函數 |
| `mieru-backend-allinone.lua` | 核心與後端的合併版單一檔案（**建議一般使用者使用此檔案**） |
| `mieru-backend-diagnostic.lua` | 診斷版後端，包含詳細的 `[mieru-diag]` 日誌輸出 |
| `mieru-backend-diagnostic-allinone.lua` | 核心與診斷版後端的合併版單一檔案 |
| `mieru-standalone-test.lua` | 使用 LuaSocket 的獨立測試客戶端 |
| `mieru-backend-mock-test.lua` | 模擬 `wa_lua_on_*` 回呼流程的測試腳本 |
| `build.lua` | 建置腳本，用於重新產生合併版檔案 |

### 建置

`*-allinone.lua` 檔案是透過將 `mieru-core.lua` 合併至各後端檔案所產生的。要重新產生這些檔案：

```bash
lua build.lua
```

此腳本會將 `mieru-core.lua` 包裹在閉包（closure）中，並與各後端檔案串接，產生：

- `mieru-backend-allinone.lua`
- `mieru-backend-diagnostic-allinone.lua`

### 本地測試

兩個測試腳本均需要 [LuaSocket](https://luarocks.org/modules/lunarmodules/luasocket) 以及一個執行中的 mieru 伺服器。

**獨立測試**——直接驗證核心協議：

```bash
lua mieru-standalone-test.lua <主機> <連接埠> <使用者名稱> <密碼> [目標主機] [目標連接埠] [協議版本] [時間偏移秒數]
```

範例：

```bash
lua mieru-standalone-test.lua 127.0.0.1 10910 myuser mypassword example.com 80 v3 0
```

預期輸出：包含 `HTTP/1.1 ...` 及 `TEST_PASS`。

**回呼模擬測試**——驗證 Shadowrocket `wa_lua_on_*` 回呼流程：

```bash
lua mieru-backend-mock-test.lua <主機> <連接埠> <使用者名稱> <密碼> [腳本路徑] [協議版本] [時間偏移秒數]
```

範例：

```bash
lua mieru-backend-mock-test.lua 127.0.0.1 10910 myuser mypassword mieru-backend.lua v3 0
```

預期輸出：包含 `HTTP/1.1 ...` 及 `[mock-test] TEST_PASS`。

## 技術細節

### 加密演算法

所有加密演算法均以純 Lua 實現，無需任何外部 C 模組或 FFI：

| 演算法 | 用途 |
|--------|------|
| XChaCha20-Poly1305 | AEAD 加密／解密（資料傳輸） |
| HChaCha20 | 延伸 nonce 子金鑰衍生 |
| ChaCha20 | 串流加密 |
| Poly1305 | 訊息驗證碼（MAC） |
| SHA-256 | 雜湊函數 |
| HMAC-SHA256 | 金鑰衍生中的 PRF |
| PBKDF2-SHA256 | 密碼衍生金鑰 |

### 位元運算相容性

腳本自動偵測 Lua 環境中可用的位元運算方式，依序嘗試：

1. `bit32` 函式庫（Lua 5.2）
2. `bit` 函式庫（LuaJIT）
3. Lua 5.3+ 原生位元運算子（`&`、`|`、`~`）
4. 純算術回退實現（適用於任何 Lua 版本）

### 協議範圍

**已支援：**

- TCP CONNECT
- mieru 串流協議封裝
- PBKDF2-SHA256 金鑰衍生（v3 參數）
- XChaCha20-Poly1305 搭配 24 位元組隱式 nonce

**尚未支援：**

- UDP associate

## 免責聲明

- 本腳本**僅供教學與學術研究用途**。
- 請確保您的使用方式符合所在國家及地區的相關法律法規。
- 作者不對因使用本腳本所產生的任何後果承擔責任。

## 授權

Use of this software is subject to the GPL-3 license.
