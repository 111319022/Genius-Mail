# Genius Mail iOS App

Genius Mail 的原生 iOS 用戶端（SwiftUI，iOS 26 以上），直接使用 `mail-worker` 的 `/api/*`，並透過 APNs 接收新郵件推播。

## 功能

- 收件匣／已寄出／星號郵件，支援「所有信箱」或單一信箱切換
- 下拉重新整理、無限捲動、前景每 20 秒自動檢查新信
- 左右滑動：已讀、星號、刪除；長按選單：回覆、轉寄、複製驗證碼…
- 多選模式：批次標為已讀、批次刪除
- 郵件內容以 WKWebView 顯示（停用信件內的 JavaScript），過寬的 HTML 信件自動縮放
- 驗證碼卡片一鍵複製
- 附件下載後以 QuickLook 預覽，可直接分享或儲存
- 寫信／回覆／全部回覆／轉寄，支援照片與檔案附件、草稿、最近收件人自動完成
- 伺服器端搜尋（寄件人、收件人、主旨、內文）
- 推播通知：寄件人＋主旨＋內文預覽；有驗證碼時可以在通知上直接「複製驗證碼」，也可以「標為已讀」或「刪除」
- App 圖示紅點顯示未讀數量
- 設定：管理信箱（新增、改名、刪除）、通知狀態、傳送測試通知

## 啟用推播（只需做一次）

### 1. 建立 APNs 金鑰

1. 到 [Apple Developer → Certificates, Identifiers & Profiles → Keys](https://developer.apple.com/account/resources/authkeys/list) 按 **+**
2. 勾選 **Apple Push Notifications service (APNs)**，建立後下載 `AuthKey_XXXXXXXXXX.p8`（只能下載一次，請妥善保存）
3. 記下 **Key ID**（10 碼）

### 2. 設定 Worker secrets

在 `mail-worker` 資料夾執行（`.p8` 檔案內容不要放進 repo）：

```bash
npx wrangler secret put apns_key < ~/Downloads/AuthKey_XXXXXXXXXX.p8
```

```bash
npx wrangler secret put apns_key_id
```

```bash
npx wrangler secret put apns_team_id
```

```bash
npx wrangler secret put apns_bundle_id
```

依序輸入：Key ID、Team ID `45SQT63B67`、Bundle ID `cc.rayisgenius.GeniusMail`。

Secrets 在每次部署之間都會保留，GitHub Actions 部署也不受影響。

### 3. 部署 Worker

推送到 `main`（GitHub Actions 會自動部署），或在 `mail-worker` 執行 `pnpm run deploy`。

## 安裝到 iPhone

1. 用 Xcode 開啟 `iOS-App/GeniusMail.xcodeproj`
2. Signing & Capabilities 已設定 Team `45SQT63B67`、自動簽署與 Push Notifications
3. 接上 iPhone 按 Run；登入後允許通知
4. 到 App 的「設定 → 傳送測試通知」確認推播正常

從 Xcode 直接安裝的版本使用 APNs **sandbox**；TestFlight 版本使用 **production**。App 會自動判斷並告訴伺服器，兩種都能收到。

## 上傳 TestFlight

1. 在 [App Store Connect](https://appstoreconnect.apple.com/apps) 建立 App（Bundle ID 選 `cc.rayisgenius.GeniusMail`，不需要送審上架）
2. Xcode 選擇 **Any iOS Device** → Product → **Archive**
3. Organizer → **Distribute App** → **TestFlight Internal Only**
4. 處理完成後在 iPhone 的 TestFlight App 安裝

每次上傳新版前，把 `CURRENT_PROJECT_VERSION`（Build）加 1。TestFlight 版本 90 天後會過期，需要重新上傳。

## 專案結構

```
GeniusMail/
├── App/          App 進入點、AppDelegate（推播回呼）
├── Core/         API client、資料模型、Keychain
├── Stores/       Session（登入狀態、信箱）、MailboxModel、Composer、PushManager
└── Views/        各畫面
```

專案使用 Xcode 的資料夾同步，在 `GeniusMail/` 底下新增 `.swift` 檔案不需要修改 `project.pbxproj`。

## 後端新增的 API

| API | 說明 |
|---|---|
| `POST /push/register` | 註冊 APNs 裝置 token（存在 KV `push_devices:{userId}`） |
| `DELETE /push/unregister` | 登出時移除裝置 |
| `GET /push/status` | 伺服器是否已設定金鑰、已註冊的裝置 |
| `POST /push/test` | 對自己的裝置傳送測試通知 |
| `GET /email/detail` | 取得單封郵件（含附件、星號） |
| `GET /email/unreadCount` | 未讀數量（App 圖示紅點） |
| `GET /email/list?keyword=` | 原有列表 API 加上關鍵字搜尋 |

收到新郵件（包含站內信）時，Worker 會推播給該使用者所有已註冊的裝置；失效的 token 會自動清除。
