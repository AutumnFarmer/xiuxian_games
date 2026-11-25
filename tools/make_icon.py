"""生成 App 图标（M8）：深色底、金色的"轮"字纹样，外圈一道转动的光环。"""
from PIL import Image, ImageDraw, ImageFilter
import math, json, os

S = 1024
img = Image.new("RGB", (S, S), (15, 17, 21))
d = ImageDraw.Draw(img)
# 背景径向渐变
for r in range(S // 2, 0, -4):
    t = r / (S / 2)
    c = (int(15 + 40 * (1 - t)), int(17 + 25 * (1 - t)), int(21 + 60 * (1 - t)))
    d.ellipse([S/2 - r, S/2 - r, S/2 + r, S/2 + r], fill=c)
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g = ImageDraw.Draw(glow)
# 外圈光环
g.ellipse([140, 140, S-140, S-140], outline=(255, 193, 7, 255), width=34)
# 八道轮辐
for k in range(8):
    a = k * math.pi / 4
    x1, y1 = S/2 + math.cos(a) * 120, S/2 + math.sin(a) * 120
    x2, y2 = S/2 + math.cos(a) * 340, S/2 + math.sin(a) * 340
    g.line([x1, y1, x2, y2], fill=(255, 213, 79, 255), width=26)
# 中心太极般的圆
g.ellipse([S/2-110, S/2-110, S/2+110, S/2+110], fill=(255, 193, 7, 255))
g.ellipse([S/2-56, S/2-56, S/2+56, S/2+56], fill=(15, 17, 21, 255))
# 一颗沿圆轨道的"本命法宝"
a = -math.pi / 4
bx, by = S/2 + math.cos(a) * 372, S/2 + math.sin(a) * 372
g.ellipse([bx-46, by-46, bx+46, by+46], fill=(244, 81, 30, 255))
blur = glow.filter(ImageFilter.GaussianBlur(28))
img = Image.alpha_composite(img.convert("RGBA"), blur)
img = Image.alpha_composite(img, glow).convert("RGB")
out = "LunHui/Resources/Assets.xcassets/AppIcon.appiconset"
img.save(os.path.join(out, "icon-1024.png"))
json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(out, "Contents.json"), "w"), indent=2)
json.dump({"info": {"author": "xcode", "version": 1}}, open("LunHui/Resources/Assets.xcassets/Contents.json", "w"), indent=2)
print("ok")
