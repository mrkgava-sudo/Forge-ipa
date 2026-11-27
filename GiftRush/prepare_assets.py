#!/usr/bin/env python3
import gzip, json, pathlib, shutil, sys
source = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2]) / "Gifts"
images = dest / "Images"
animations = dest / "Animations"
images.mkdir(parents=True, exist_ok=True)
animations.mkdir(parents=True, exist_ok=True)
data = json.loads((source / "data" / "gifts.json").read_text())
items = []
for gift in data["gifts"]:
    name = gift["filename"]
    png = source / "assets" / "png" / f"{name}.png"
    tgs = source / "assets" / "tgs" / f"{name}.tgs"
    shutil.copy2(png, images / f"{name}.png")
    raw = gzip.decompress(tgs.read_bytes())
    json.loads(raw)
    (animations / f"{name}.json").write_bytes(raw)
    meta = gift.get("metadata", {})
    items.append({
        "id": gift["id"], "filename": name,
        "stars": meta.get("stars"),
        "limited": bool(meta.get("limited", False)),
        "soldOut": bool(meta.get("sold_out", False))
    })
(dest / "gifts.json").write_text(json.dumps(items, ensure_ascii=False), encoding="utf-8")
print(f"Prepared {len(items)} gifts with local Lottie JSON animations")
