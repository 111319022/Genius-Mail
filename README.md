<p align="center">
    <img src="mail-vue/public/logo.svg" width="88px" />
    <h1 align="center">Genius Mail</h1>
    <p align="center">架在 Cloudflare 上的個人信箱服務，附原生 iOS App 與推播通知 😎</p>
    <p align="center">
        <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" /></a>
        <img src="https://img.shields.io/badge/Cloudflare-Workers-F38020?logo=cloudflare&logoColor=white" />
        <img src="https://img.shields.io/badge/iOS-26%2B-000000?logo=apple&logoColor=white" />
    </p>
</p>

## 簡介

Genius Mail 是跑在 Cloudflare Workers 上的 Serverless 信箱服務：一個網域就能建立多個信箱地址，收信、寄信、附件都不需要自己的伺服器。

本專案 fork 自 [maillab/cloud-mail](https://github.com/maillab/cloud-mail)，在原版的基礎上改成繁體中文、重新設計介面、加上註冊審核，並新增原生 iOS App 與 APNs 推播。

- 網頁版：<https://mail.rayisgenius.cc>
- iOS App：[iOS-App/](iOS-App/)（自用／TestFlight，未上架）

## 和原版 Cloud Mail 的差異

| 項目 | 說明 |
|---|---|
| 🇹🇼 繁體中文 | 前端、後端訊息與預設資料全面改為繁體中文（台灣用語），預設語言為繁中 |
| 🎨 新介面 | 簡約的 B2B 風格、Inter 字型、淺色側欄，登入頁改為分割畫面與手繪表情符號；品牌改為 Genius Mail |
| 📱 iOS App | SwiftUI 原生 App：收件匣、搜尋、寫信、附件預覽、驗證碼一鍵複製、多信箱切換 |
| 🔔 APNs 推播 | 收到新信時推播到 iPhone，通知上可直接複製驗證碼、標為已讀或刪除 |
| ✅ 註冊審核 | 新註冊的帳號需要管理員核准才能登入，待審核帳號不會收信，管理員信箱會收到申請通知 |
| 📊 Resend 額度 | 系統設定與使用者選單顯示 Resend 已用額度，可手動重新整理 |
| 🛠️ 附件修正 | `/attachments/`、`/static/` 改從實際設定的儲存空間（R2 / S3）讀取，並正確處理中文檔名 |
| 🔍 新 API | 單封郵件、未讀數量、關鍵字搜尋、推播裝置註冊（見下方「新增的 API」） |

## 功能

- **💰 低成本**：部署在 Cloudflare Workers，搭配 D1、KV、R2，不需要伺服器
- **📧 收發信**：用 Resend 寄信，支援群發、內嵌圖片與附件，可查看寄送狀態
- **📦 附件**：收發附件，存放在 R2
- **🔢 驗證碼辨識**：用 Workers AI 自動抓出郵件中的驗證碼
- **📱 iOS App 與推播**：見 [iOS-App/README.md](iOS-App/README.md)
- **💻 響應式網頁**：電腦與手機瀏覽器都能用，也可以加入主畫面當 PWA
- **🛡️ 管理功能**：使用者與郵件管理、RBAC 權限、註冊審核
- **🔁 轉寄**：收到的信可以轉到 Telegram Bot、其他信箱或 Webhook
- **📡 開放 API**：用 API 批次建立使用者、多條件查詢郵件
- **📈 數據統計**：用 ECharts 顯示系統數據與郵件成長
- **🤖 人機驗證**：整合 Turnstile，防止機器人大量註冊

## 技術棧

| 層級 | 技術 |
|---|---|
| 平台 | [Cloudflare Workers](https://developers.cloudflare.com/workers/) |
| 後端 | [Hono](https://hono.dev/)、[Drizzle ORM](https://orm.drizzle.team/) |
| 資料 | [D1](https://developers.cloudflare.com/d1/)（資料庫）、[KV](https://developers.cloudflare.com/kv/)（快取）、[R2](https://developers.cloudflare.com/r2/)（檔案） |
| 網頁前端 | [Vue 3](https://vuejs.org/)、[Element Plus](https://element-plus.org/) |
| iOS | SwiftUI（iOS 26+）、WKWebView、QuickLook |
| 寄信 | [Resend](https://resend.com/) |
| 推播 | Apple Push Notification service（Worker 直接以 ES256 JWT 呼叫 APNs） |
| AI | Workers AI（驗證碼辨識） |

## 目錄結構

```
Genius-Mail
├── mail-worker          # Cloudflare Worker 後端（Hono）
│   ├── src
│   │   ├── api          # API 路由
│   │   ├── email        # 收信處理（Email Routing 進來的信）
│   │   ├── service      # 商業邏輯（含 push-service.js：APNs 推播）
│   │   ├── entity       # Drizzle 資料表定義
│   │   ├── init         # 資料庫初始化與升級
│   │   ├── security     # 登入驗證與權限
│   │   └── i18n         # 後端訊息（繁中／英文）
│   ├── wrangler.toml    # 正式環境設定
│   └── wrangler-dev.toml
├── mail-vue             # 網頁前端（Vue 3），build 到 mail-worker/dist
└── iOS-App              # 原生 iOS App（SwiftUI）
    ├── GeniusMail
    └── GeniusMail.xcodeproj
```

## 部署

### 自動部署

`cloud-mail` Worker 已透過 **Cloudflare Workers Builds** 連結這個 GitHub repo：

- push 到 `main` 就會自動 build 並部署（根目錄 `/mail-worker`，build 時會一併編譯 `mail-vue`）
- 只改到 `iOS-App/`、`doc/` 或 `*.md` 的 push **不會**觸發部署
- `.github/workflows/deploy-cloudflare.yml` 是原版專案留下的 workflow，目前已在 GitHub 上停用

### 手動部署

```bash
cd mail-worker
npx wrangler deploy
```

build 步驟會用到 `pnpm`；本機沒有安裝時，可以先執行 `npm i -g pnpm`。

### Secrets

機密設定都存成 Worker secret，不放在 repo 裡：

| 名稱 | 說明 |
|---|---|
| `jwt_secret` | 登入 token 簽章金鑰，也用於資料庫初始化網址 |
| `apns_key` | APNs 金鑰（`.p8` 檔內容） |
| `apns_key_id` | APNs Key ID |
| `apns_team_id` | Apple Developer Team ID |
| `apns_bundle_id` | iOS App 的 Bundle ID（`cc.rayisgenius.GeniusMail`） |

```bash
cd mail-worker
npx wrangler secret put jwt_secret
```

APNs 金鑰的申請步驟見 [iOS-App/README.md](iOS-App/README.md#啟用推播只需做一次)。

### 資料庫初始化與升級

第一次部署，或更新後有新增資料表欄位時，開啟一次：

```
https://mail.rayisgenius.cc/api/init/<jwt_secret>
```

## 本機開發

```bash
# 後端：http://127.0.0.1:8787
cd mail-worker
npx wrangler dev --config wrangler-dev.toml
```

第一次啟動後開啟 `http://127.0.0.1:8787/api/init/<wrangler-dev.toml 裡的 jwt_secret>` 建立本機資料庫。

```bash
# 前端：開發伺服器會呼叫 127.0.0.1:8787 的後端
cd mail-vue
pnpm install
pnpm dev
```

iOS App 用 Xcode 開啟 `iOS-App/GeniusMail.xcodeproj`；在登入畫面的「伺服器設定」可以改成本機後端網址。

## 新增的 API

除了原版的 API，另外新增了這些（都需要登入）：

| API | 說明 |
|---|---|
| `GET /api/email/detail?emailId=` | 取得單封郵件（含附件與星號狀態） |
| `GET /api/email/unreadCount` | 未讀郵件數量 |
| `GET /api/email/list?keyword=` | 郵件列表加上關鍵字搜尋（寄件人、收件人、主旨、內文） |
| `POST /api/push/register` | 註冊 iOS 推播裝置 |
| `DELETE /api/push/unregister` | 移除推播裝置 |
| `GET /api/push/status` | 推播設定狀態與已註冊裝置 |
| `POST /api/push/test` | 傳送測試通知到自己的裝置 |

## 致謝

- 原始專案：[maillab/cloud-mail](https://github.com/maillab/cloud-mail)，感謝原作者與所有貢獻者

## 授權

[MIT](LICENSE)
