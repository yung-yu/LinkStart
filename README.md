# LinkStart

LinkStart 是一個為 macOS 打造的原生輔助工具，專門用於優化 `scrcpy` 的使用體驗。它透過 SwiftUI 構建，提供了直觀的圖形化介面，讓您可以輕鬆地從 Mac 上查看並啟動 Android 裝置中的應用程式。

![LinkStart Interface Screenshot](./screenshot/screenshot.png)

## ✨ 主要功能

- **🚀 智慧啟動**：自動掃描 Android 裝置中安裝的第三方應用程式，點擊即可透過 `scrcpy` 啟動。
- **🖥️ 介面優化**：精心設計的雙層狀態列排版，讓各項操控選項、螢幕解析度設定及搜尋欄位更加清晰且不擁擠。支援一鍵過濾系統應用程式 (System Apps)。
- **📱 多裝置支援**：支援同時連接多台 Android 設備，並可在介面上直觀切換。
- **🎨 深度客製化**：
    - **自定義標題**：投影視窗名稱會自動設為 APP 的名稱。
    - **動態圖標**：MacOS Dock 與視窗圖標會自動變更為該 APP 的專屬圖誌。
    - **解析度設定**：支援自定義虛擬顯示器的寬與高。
    - **New Display 模式**：自由勾選是否針對個別 APP 開啟獨立 `--new-display` 視窗。
- **🛠️ 自動化環境部署**：啟動時自動檢查 `adb` 與 `scrcpy` 依賴環境，若缺失則自動背景執行 Homebrew 協助安裝。

## 📋 系統需求

- **macOS**: 12.0 (Monterey) 或更高版本。
- **Homebrew**: 用於自動安裝與更新 `adb` 及 `scrcpy`。
- **Android 裝置**: 需啟動「USB 偵錯」模式。

## 🛠️ 安裝與開發

本專案使用原生 Swift 編譯，不需要安裝 Xcode 大手筆設定。

1. **複製專案到本地**：
   ```bash
   cd /androidDeviceMirror/LinkStart
   ```

2. **編譯應用程式**：
   執行腳本，這將會生成 `LinkStart.app`。
   ```bash
   chmod +x build.sh
   ./build.sh
   ```

3. **啟動**：
   ```bash
   open LinkStart.app
   ```

## 📖 使用說明

1. 開啟程式後，它會自動檢查依賴環境。
2. 連接您的安卓手機，確保在手機上授權偵錯。
3. 若有多台裝置，可從右上角的下拉選單選擇目標。
4. 在設定區塊可以調整您想要的解析度以及是否開啟新虛擬顯示器。
5. 點擊畫面上的應用程式，即可開啟投影。

## 📄 授權協議

本專案採用 [MIT License](LICENSE) 授權。您可以自由地使用、修改與分發。

---

*Powered by [scrcpy](https://github.com/Genymobile/scrcpy)*
