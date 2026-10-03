---
name: dev-infotracker
description: 開發 infotracker2 的任務追蹤、查詢遊戲任務 ID，或重新載入實機測試時使用。
---

# infotracker2 開發

- 查詢未知任務 ID：讀取 [references/quest-id.md](references/quest-id.md)。
- 修改插件及實機測試：讀取 [references/live-test.md](references/live-test.md)。
- 任務組位於 `quest_data.lua`，顯示名稱位於 `locale.lua`。每日組使用 `daily.items`；未指定 `max` 時分母為 ID 數量。
- 任務資料調整保留既有 key。
