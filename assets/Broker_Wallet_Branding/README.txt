BROKER WALLET — ORIGINAL FIGMA ARTWORK

logo.svg: tightly cropped transparent vector logo for Flutter UI.
logo.png: transparent PNG alternative.
app_icon_master.png / app_icon_ios.png: 1024x1024 RGB, white background, no alpha, no rounded corners.
google_play_icon.png: 512x512 RGB, white background.
android_icon_foreground.png: 1024x1024 transparent, artwork scaled to 80% of original canvas placement.
android_icon_background.png: 1024x1024 white background (or use #FFFFFF).
android_icon_foreground.svg: editable vector equivalent.
app_icon_master.svg: editable vector master.

Use Android foreground and background as separate adaptive-icon layers. Foreground already includes padding; avoid automatically adding further inset. Native splash configuration requires platform-specific PNG assets; logo.svg is for Flutter-rendered UI.

Original artwork geometry, gradients, and colors preserved. These are source assets; platform launcher resources still need generating in the Flutter project.
