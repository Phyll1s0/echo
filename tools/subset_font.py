# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools>=4.60"]
# ///
"""Rebuild the bundled Chinese font after editing translations: uv run tools/subset_font.py."""
from pathlib import Path
from urllib.request import urlretrieve
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

root = Path(__file__).resolve().parents[1]
source = root / 'builds/NotoSansSC.ttf'
source.parent.mkdir(exist_ok=True)
if not source.exists():
    urlretrieve('https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf', source)
font = instantiateVariableFont(TTFont(source), {'wght': 400}, inplace=True)
options = subset.Options()
options.hinting = False
options.layout_features = ['*']
selection = subset.Subsetter(options=options)
text = (root / 'i18n/zh_CN.po').read_text()
text += ''.join(path.read_text() for path in (root / 'scripts').glob('*.gd'))
selection.populate(text=text)
selection.subset(font)
font.save(root / 'assets/fonts/NotoSansSC-Echo.ttf')
print('Bundled Chinese font updated at weight 400; license: assets/fonts/noto-OFL.txt')
