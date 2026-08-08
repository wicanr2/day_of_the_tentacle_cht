瘋狂時代（Day of the Tentacle）繁體中文化
====================================

包含《瘋狂時代》本體，以及泰德表哥電腦裡那套完整的一代《瘋狂大樓》——
兩個都是中文的。


需要什麼
--------

《Day of the Tentacle》的 CD 版原始資料，也就是這幾個檔：

    TENTACLE.000
    TENTACLE.001
    monster.sof        （語音包，沒有的話字幕照常，只是沒聲音）
    MANIAC/*.LFL       （泰德電腦裡的一代，54 個檔）

Steam、GOG 的《Day of the Tentacle Remastered》**不適用**——那是重製版，
資料格式不同。要的是 1993 年的原始 CD 版資料。


怎麼套用
--------

把整包解開到任何地方，然後：

  Windows   把原版資料夾拖到「套用中文化.bat」上
  Linux     ./套用中文化.sh /路徑/到/原版資料夾
  macOS     ./套用中文化.command /路徑/到/原版資料夾

腳本會把原版複製一份到這個資料夾的 game/ 底下再動手，**不會改到你的原版**。

跑完之後：

  Windows   執行遊戲.bat
  Linux     ./執行遊戲.sh
  macOS     開啟 ScummVM.app


怎麼玩到泰德電腦裡的一代
------------------------

遊戲中期，用伯納到二樓泰德的房間，打開那台電腦。ScummVM 會把一代當成
另一個遊戲啟動，玩完（或按 F5 離開）就回到《瘋狂時代》，進度原封不動。

這一步需要 scummvm.ini 裡的兩個 target 都在。本包已經設好，
不要手動改 `easter_egg=maniac-zh` 那一行。


音樂：MT-32
-----------

包裡附了 Roland MT-32 的 ROM 與設定，遊戲直接用 MT-32 音源，不是 AdLib。
1993 年的 iMUSE 配樂是照 MT-32 寫的，音色比 FM 合成的 AdLib 厚很多。

想換回 AdLib，把 `scummvm.ini` 裡 `[dott-zh]` 底下的 `music_driver=mt32`
改成 `adlib` 即可。

啟動時 log 會有一行「Unable to open CM32L_CONTROL.ROM ... Falling back to MT32」，
那是 ScummVM 先找 CM-32L（MT-32 的後續機種）找不到才用 MT-32，不是錯誤。

泰德電腦裡的一代沒有 MIDI（SCUMM v1 只有 PC speaker / PCjr），不受這一段影響。


中文語音（有語音包時才有）
--------------------------

遊戲中按 **Ctrl+T** 循環切換語音包，畫面上方會跳出目前用的是哪一組：

  Original (English)    1993 年的英文原音
  Taiwanese Mandarin    台灣中文合成語音，音高照原音的基頻挑
  Cloned voices         用英文原音當範本的聲音克隆，角色講中文但音色是自己的

選擇會記進 scummvm.ini，下次開遊戲沿用。切換時正在講的那句會被截斷，
下一句就換成新的語音。

語音包是放在遊戲資料夾裡的 `monster-tw.sof`（台式中文）與 `monster-cl.sof`
（克隆），找不到就自動退回英文原音，畫面上會說明。**公開的散布包不含語音包**
（見下方版權），只有英文原音會照常運作。


macOS 第一次開啟
----------------

包裡的 .app 沒有 Apple 開發者簽章，第一次雙擊 Gatekeeper 會擋下來
（「無法打開，因為無法驗證開發者」）。兩種解法擇一：

  在 Finder 裡對 ScummVM.app 按右鍵 →「打開」→ 再按一次「打開」

或在終端機：

  xattr -dr com.apple.quarantine ScummVM.app

想自己重簽也可以：

  codesign --force --deep --sign - ScummVM.app


已知的事
--------

* 沒有語音包時語音是英文原音，字幕是中文。
* 工作人員名單維持原文（那些行靠空白對齊，改動會破版），只有職稱翻了。
* 一代的媒體得獎評語裡，雜誌名維持原文。
* 遊戲內建的存讀檔畫面已中文化，但一般建議用 ScummVM 自己的存檔功能（F5）。
* ScummVM 自己的選單介面是英文的（三平台一致）。遊戲內的中文不受影響。
* macOS 版是在 GitHub Actions 上編的 universal binary（arm64 + x86_64），
  但打包流程在 Linux 上跑，**沒有在實體 Mac 上實測過**。遇到問題請回報。


版權
----

本包只含中文化的產物（譯文、字型、修補過的引擎）與 ScummVM。
遊戲本體、語音、美術的著作權屬原作者，需自備。

中文語音包不在散布範圍內：它是原版 `monster.sof` 的改造版（沒被翻譯到的
113 段仍是原音），而且合成用的是微軟 Edge 的線上服務，兩邊都不允許再散布。

MT-32 ROM 的著作權屬 Roland，同樣不在散布範圍內。

ScummVM 依 GPLv2 授權，原始碼與本專案的修補檔見：
https://github.com/wicanr2/day_of_the_tentacle_cht
