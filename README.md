# AIHub — App chat đa AI cho iPhone

App chat AI trên iOS (SwiftUI), cho phép **chọn và chuyển đổi giữa nhiều AI** ngay trong màn hình chat:

| AI | Kiểu API | Lấy API key |
|---|---|---|
| OpenAI (ChatGPT) | OpenAI | https://platform.openai.com/api-keys |
| Anthropic (Claude) | Anthropic | https://console.anthropic.com |
| Google Gemini | Gemini | https://aistudio.google.com/apikey |
| OpenRouter (một key, rất nhiều model) | OpenAI-compatible | https://openrouter.ai/keys |
| Groq (siêu nhanh) | OpenAI-compatible | https://console.groq.com/keys |
| DeepSeek | OpenAI-compatible | https://platform.deepseek.com |
| Ollama (chạy local, miễn phí) | OpenAI-compatible | Không cần key |
| Tùy chỉnh (máy chủ OpenAI-compatible bất kỳ) | OpenAI-compatible | Tùy |

Tính năng:
- ✅ Chọn AI nhanh qua menu trên thanh điều hướng, **mỗi hội thoại có thể dùng AI khác nhau**
- ✅ **Streaming** — câu trả lời hiện dần theo từng chữ
- ✅ Nhiều hội thoại, tự lưu vào bộ nhớ máy
- ✅ Đổi model cho từng AI, đổi Base URL (hỗ trợ proxy/endpoint riêng)
- ✅ System prompt chung
- ✅ Dừng câu trả lời giữa chừng, tự xuống cuối trang khi stream

---

## Cấu trúc dự án

```
AIHub/
├── AIHub.xcodeproj/          # Project Xcode (Xcode 16+)
├── AIHub/                    # Toàn bộ source code
│   ├── AIHubApp.swift        # Entry point
│   ├── Models.swift          # Danh sách AI providers + model dữ liệu
│   ├── AIService.swift       # Gọi API streaming (OpenAI / Anthropic / Gemini)
│   ├── SettingsStore.swift   # Lưu API key, model, base URL
│   ├── ConversationStore.swift # Lưu lịch sử chat
│   ├── RootView.swift
│   ├── ChatView.swift        # Màn hình chat chính
│   ├── ConversationListView.swift # Lịch sử chat
│   ├── SettingsView.swift    # Màn hình cài đặt
│   └── Assets.xcassets/      # Icon + màu accent
├── .github/workflows/build-ipa.yml # Build IPA tự động bằng GitHub Actions
└── README.md
```

Bundle identifier: `com.yenth.aihub` (đổi trong `project.pbxproj` nếu muốn, nhưng **phải khớp với provisioning profile** khi ký).

---

## Cách 1 — Build bằng Xcode (cần máy Mac)

1. Mở `AIHub.xcodeproj` bằng **Xcode 16+**.
2. Chọn target **AIHub** → tab **Signing & Capabilities** → tick **Automatically manage signing**, chọn Team của bạn (Apple ID cá nhân cũng được).
3. Chọn thiết bị **Any iOS Device (arm64)** → menu **Product → Build** (hoặc Archive).
4. Tìm file `AIHub.app` trong DerivedData:
   `~/Library/Developer/Xcode/DerivedData/AIHub-*/Build/Products/Release-iphoneos/` (hoặc Debug-iphoneos nếu dùng Build).
5. Đóng gói thành IPA:

```bash
mkdir Payload
cp -r /path/to/AIHub.app Payload/
zip -r AIHub-unsigned.ipa Payload
rm -rf Payload
```

---

## Cách 2 — Build IPA bằng GitHub Actions (KHÔNG cần Mac)

1. Tạo repository trên GitHub và push thư mục `AIHub/` lên (repo này).
2. Vào tab **Actions** → workflow **"Build unsigned IPA"** sẽ chạy tự động (hoặc bấm **Run workflow**).
3. Khi xong, tải artifact **AIHub-unsigned-ipa** về — đó là file **IPA chưa ký**.

> IPA chưa ký + zsign chính là combo bạn cần. Xcode trên Actions sẽ tự sinh Info.plist (đã bật `GENERATE_INFOPLIST_FILE`).

---

## Ký IPA bằng zsign

### Chuẩn bị

Bạn cần 3 thứ khớp với nhau:
1. **Chứng chỉ** (`cert.p12` + mật khẩu) — từ Apple Developer account (thanh toán $99/năm) hoặc chứng chỉ phát hành từ công cụ free-signing.
2. **Provisioning profile** (`*.mobileprovision`) chứa `com.yenth.aihub` và UDID iPhone của bạn (nếu dùng profile development/ad-hoc).
3. **Entitlements** (`entitlements.plist`) khớp với profile.

Ví dụ `entitlements.plist` cho development profile (thay `TEAMID` bằng Team ID của bạn):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>TEAMID.com.yenth.aihub</string>
    <key>get-task-allow</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>TEAMID.com.yenth.aihub</string>
    </array>
</dict>
</plist>
```

### Các bước ký

```bash
# 1. Giải nén IPA chưa ký
unzip AIHub-unsigned.ipa -d signed
cd signed

# 2. Thả provisioning profile vào app (zsign cần nó để cài được)
cp /path/to/MyApp.mobileprovision Payload/AIHub.app/embedded.mobileprovision

# 3. Đóng gói lại
zip -qry ../AIHub-prepared.ipa Payload
cd ..

# 4. Ký bằng zsign
zsign -k cert.p12 -p "MAT_KHAU_P12" -m entitlements.plist \
      -o AIHub-signed.ipa AIHub-prepared.ipa

# (Nếu dùng chứng chỉ + key riêng rẽ thay vì p12:)
# zsign -k key.key -c cert.pem -m entitlements.plist -o AIHub-signed.ipa AIHub-prepared.ipa
```

> 💡 Mẹo: có thể ký trực tiếp và ghi đè: `zsign -k cert.p12 -p "pass" -m ent.plist AIHub-prepared.ipa` (không cần `-o`).

### Cài lên iPhone

Chọn 1 trong các cách:
- **Finder (macOS)** / **iTunes (Windows)**: kéo file IPA vào mục thiết bị.
- **Apple Configurator 2**: kéo IPA vào iPhone.
- **AltStore / Sideloadly**: cài trực tiếp file IPA đã ký.

Lưu ý quan trọng:
- iPhone phải **tin tưởng chứng chỉ**: vào *Cài đặt → Cài đặt chung → Quản lý VPN & Thiết bị* → Trust profile.
- Apple ID miễn phí: app hết hạn sau **7 ngày**, tối đa 3 app. Paid account: **365 ngày**.
- Nếu ký bằng zsign với profile development, **UDID iPhone phải có trong profile**, nếu không app sẽ không cài được (lỗi *Unable to install*).

---

## Sử dụng app

1. Mở app → bấm **⚙️ (gear)** trên góc trái.
2. Nhập **API key** cho các AI bạn muốn dùng (chỉ cần nhập AI nào bạn dùng).
3. Bấm menu tên AI ở **giữa thanh điều hướng** để chuyển AI bất kỳ lúc nào — mỗi chat nhớ AI riêng của nó.
4. Chat! Câu trả lời stream trực tiếp. Nút **⏹** để dừng, **✉️+** để tạo chat mới, **🕓** để xem lịch sử.

### Lưu ý về Ollama (local)
iOS chặn kết nối `http://` thường (ATS). Muốn dùng Ollama trên máy tính qua Wi-Fi:
- Cách dễ nhất: chạy proxy HTTPS (ví dụ Cloudflare Tunnel / Tailscale serve) rồi điền URL HTTPS vào ô Base URL của Ollama hoặc Custom.
- Hoặc thêm exception `NSAppTransportSecurity → NSAllowsArbitraryLoads` trong target AIHub (tab Info của Xcode) trước khi build — chỉ nên dùng cho mục đích cá nhân.
