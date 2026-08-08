# theme.sh —— 這部片專屬的設計 token
#
# THEME_NAME 用來錨定決策：色票全部從遊戲本身取，不是憑喜好挑。
# 取法：實機畫格 → `convert -resize 120x120 -colors 10 -format %c histogram:info:-`
#   夜空最暗 #05050D、夜空主色 #1F1D6D（開場片尾的星空）
#   標題 logo 的螢光綠 #49F571、暗綠 #2A8C42（做浮雕陰影）
#   logo 的洋紅紫 #9B3EBB（也是紫色觸手的紫）
THEME_NAME="螢光綠與夜空紫"

BG_DEEP='#05050D'
BG_MID='#1F1D6D'
BG_LITE='#292884'
ACCENT='#49F571'      # 螢光綠：標題、框線、強調
ACCENT_DK='#2A8C42'   # 綠的暗部：浮雕陰影
ACCENT2='#9B3EBB'     # 洋紅紫：副標、角色名
TEXT='#EAF4FF'
DIM='#8A93C8'

# 卡通喜劇用粗黑體。SKILL 說「黑體＝手遊味」是針對西方奇幻；
# 1993 年的卡通式喜劇用 Serif 反而過於正經。
FONT_TITLE=/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc
FONT_BODY=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc

W=1280; H=720; FPS=25
PACE_CARD=4.5; PACE_CLIP=8       # 喜劇：快切
