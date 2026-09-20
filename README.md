# InfoTracker v2（資訊追蹤）

ArcheRage 的任務與角色資訊追蹤插件，提供分類懸浮窗、追蹤設定、每日挑戰材料明細，以及副本建隊操作。

本專案基於 infotracker 的部分程式與功能延伸開發，原作者為 **Discord @Nevermore (奈奈呀)**；依作者同意維持原始碼公開、免費使用。作者授權原話、沿用範圍與 UI 概念參考見 [COPYRIGHT.md](COPYRIGHT.md)。

## 安裝

可透過 [插件管理器](https://github.com/BaiHaoWei666/archerage-addons-installer/releases/latest) 安裝及更新，無須提供權杖。

手動安裝：從 [本專案 Release](https://github.com/BaiHaoWei666/archerage-addon-infotracker2/releases/latest) 下載 `infotracker2.zip`，解壓縮到遊戲的 `Addon` 目錄，使 `Addon/infotracker2/toc.g` 存在，再於遊戲啟用或重新載入插件。請下載 Release 附件，不使用 Source code ZIP。

## 功能與操作

文件以繁體中文說明，遊戲內中文介面使用簡體。

- **任務追蹤**：每日、生活、週常及其他任務依 ID 池計算進度，同名任務合併顯示；點名稱展開明細。
  「領地（安息）」包含農家之需（9380）、領地活動的成果（9381）、監督所的悠閒的一天（10153），每日共 3 個任務。ID 依 2026-09-20 使用者提供的遊戲已接任務查詢截圖核對；新增群組的實機顯示與完成狀態尚待驗證。
- **每日挑戰**：與其他追蹤項目共用清單流程；特產挑戰可展開材料。按兩下可交易材料可開啟拍賣場搜尋，非賣品不提供搜尋。
- **角色資訊**：顯示祝福、服裝期限與每日／公會任務等狀態。
- **今日淨收入**：累計經驗、金幣、生活點與榮譽；每日歸零，可在設定頁重置。
- **副本**：顯示已進入次數；在懸浮窗按兩下副本可開啟建隊確認，選擇是否邀請隊伍成員。

懸浮窗依分類切頁，只顯示勾選追蹤的項目。標題可展開分類選單；按住 Shift 並拖曳標題列可移動。點齒輪開啟設定。

設定頁可勾選項目、調整順序、展開明細；本頁未全部追蹤時提供「全部加入追蹤」，全部追蹤時切為「全部移除追蹤」。面板設定調整分類順序、可見頁面、大小、字型與背景不透明度。「操作說明」頁提供移動、副本與材料操作提示。頁面、位置及外觀會存檔。

狀態顏色：紅色代表未開始或異常，橙色代表進行中，綠色代表完成或正常。材料配方以名稱比對，不依賴目標物品 ID；無法唯一比對時不猜測配方。

設定視窗頂端「說明」旁提供「查询ID」分頁，輸入任務名稱片段後點擊查詢，在本機聊天框列出符合的已接任務名稱與 ID，頁面同步顯示筆數。空白關鍵字不查詢；英文忽略大小寫，符號按原文比對。

### 位置重置診斷

載入時若沒有可用的懸浮窗座標，插件會使用預設位置，並在本機聊天框顯示原因與 `[ITV2 position 段號/總段數]` 存檔診斷。首次使用或尚未儲存位置會顯示對應提示，不代表存檔損壞；有效座標會在初始化顯示後與標題欄實際位置比對（容許 1 像素取整誤差）；不一致或無法取得實際座標時，同樣輸出診斷，另列預期座標、實際座標及 UI 縮放倍率。位置一致則不輸出。只檢查載入當下，不監控後續移動。此功能長期保留，每次載入最多輸出一次，不會修改存檔或自動傳送回報。

若移動過懸浮窗，重新登入卻回到預設位置，請提供插件版本、重新登入方式，以及提示和各段診斷內容。診斷保留讀取當下的 `itv2_settings`，優先列出位置相關的 `popout`；內容過長或巢狀過深會明確提示僅顯示部分內容。它不包含另行儲存的收入資料。

## 開發與測試

### 資料更新方式

- 任務與每日挑戰不做每秒／每五秒輪詢。載入及重新進入世界時掃一次已接任務日誌、讀取配置任務的完成狀態與七格挑戰，建立兩個視窗共用的記憶體快取。
- `QUEST_CONTEXT_UPDATED(id, action)` 的 `started`、`updated`、`completed`、`dropped` 更新單一任務狀態；`reset` 僅清除該 ID 的完成狀態，保留仍接取中的狀態，不清空其他任務或觸發七格全讀。
- 已知挑戰 ID 的通知只讓對應格失效；更換時的 `dropped`、`START_TODAY_ASSIGNMENT`，以及無法定位格子的 `UPDATE_TODAY_ASSIGNMENT`，標記七格待重讀。未顯示挑戰頁時延後至切入才讀取；連續通知於下一幀合併刷新，兩視窗共用結果。
- 角色資訊保留原有刷新頻率（設定窗一秒、懸浮窗五秒），每項讀取結果共用一秒快取。收入與副本維持原本資料更新方式。未顯示的分類不重畫；內容未變不寫文字，結構未變不重排。滑鼠懸停與延遲操作仍使用 UI 計時。

2026-09-20 使用者實機截圖已確認一般任務的接取、推進、交付、放棄，以及進場時單一任務的 `reset`；更換挑戰觀察到舊 ID `dropped`、新 ID `started` 與 `START_TODAY_ASSIGNMENT`。本版依約假設跨日也會發送單 ID `reset`，沒有跨日補查輪詢；跨日／每週通知是否完整，以及正式事件驅動版本的實機顯示仍待驗證。持續出現的 `CLEAR_COMPLETED_QUEST_INFO`／`UPDATE_COMPLETED_QUEST_INFO` 不作為重置或刷新依據。臨時事件輸出已移除。

repo 根目錄就是插件目錄，可放在管理器的 `addons/infotracker2/`，並讓遊戲 `Addon/infotracker2` Junction 指向它。這是獨立 Git repo，提交與推送均在本目錄執行。

```powershell
python -m pip install -r scripts/test-requirements.txt
./scripts/test.ps1
python scripts/build-release.py
```

測試以 Lua 5.1 執行語法檢查與模擬遊戲 API 的回歸案例，涵蓋任務、挑戰、捲動與查詢／UI 更新次數；它不等同於實機 FPS 或遊戲操作驗證。實機測試流程見 [.agents/skills/dev-infotracker/SKILL.md](.agents/skills/dev-infotracker/SKILL.md)。

| 路徑 | 用途 |
|---|---|
| `toc.g`、`main.lua` | 載入順序與初始化 |
| `quest_data.lua`、`specialty_data.lua` | 任務池與特產資料 |
| `sources/`、`items.lua` | 各資料來源與項目整合 |
| `windows/` | 設定、懸浮窗與共用 UI |
| `settings.lua`、`locale.lua` | 使用者設定與遊戲顯示文字 |
| `manifest.json` | 版本、管理器介紹、changelog、封裝白名單 |
| `tests/`、`scripts/` | 回歸測試與 Release 封裝 |

保留既有設定 key：`itv2_settings`、`itv2_income_<角色名>`。新增任務時同時維護資料與語系；新增來源時更新 `toc.g`。

## 發布

使用者未明確要求升版或發布時，保留目前版本；一般修改、測試、提交或推送不自動升版。執行封裝時會同步本機 version.txt，在 dist 產生 ZIP、含 SHA-256 的 manifest、說明及圖示，並核對 ZIP 內容。開發 Junction 的版本也須讀回確認。

push main／PR 會執行 CI；推送單一 `v<版本>` tag 會在測試成功後發布上述附件。已發布版本不重用。完整整合格式見 [管理器插件規格](https://github.com/BaiHaoWei666/archerage-addons-installer/blob/main/docs/addon-format.md)。
