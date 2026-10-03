# 本機開發與測試

## 目錄

- 原始碼：本插件 repo 根目錄。
- 遊戲目錄：ArcheRage 的 `Addon/infotracker2`；使用開發 Junction 時，連結至本插件 repo。
- 使用開發 Junction 時，原始碼與遊戲目錄讀取同一份檔案，重新載入即可讀取修改。Junction 驗證依根目錄 AGENTS.md 的開發規範。

## 實機測試

1. 完成修改後，請使用者操作：Esc → 附加組件管理器 → infotracker2 最右側圓形箭頭。齒輪是設定。
2. 依 computer-use skill 的可用能力讀取遊戲畫面；遊戲操作遵循根目錄 AGENTS.md 的開發規範。
3. 從本機聊天框確認載入訊息，查看新項目、展開名稱及狀態。查詢需求讀取 [quest-id.md](quest-id.md)。
4. 移除本次探針與 `toc.g` 載入行、還原暫時開關，再請使用者重新載入正式版本。

`ITV2.Chat` 使用 `X2Chat:DispatchChatMessage(CMF_SYSTEM, ...)`，只顯示本機訊息。此輸出未出現在當次 `Chat.log` 或 `ArcheRage.log`，應直接讀取遊戲聊天框畫面。
