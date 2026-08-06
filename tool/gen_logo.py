"""Genera los assets del logotipo de Attra a partir del ARTE ORIGINAL.

Fuente de verdad: tool/brand/attra_logo_source.png (marca blanca sobre negro).
Ese fichero NO se toca; de el se derivan los assets que usa la app.

Por que no se usa el original tal cual:
  - No es cuadrado (661x643), asi que al generar el icono se DEFORMA.
  - Mide menos de 1024 px, y el icono de marketing de App Store exige
    1024x1024: escalarlo hacia arriba deja los bordes blandos justo en la
    imagen que revisa Apple.
  - El splash necesita la marca con TRANSPARENCIA; el original lleva el fondo
    negro incrustado y sobre el degradado se ve un cuadrado recortado.

Como se resuelve sin redibujar la marca: se extrae su silueta (es blanco puro
sobre negro puro), se recorta, se centra en un lienzo cuadrado conservando la
proporcion original y se re-renderiza a 1024 px con supermuestreo. La FORMA es
exactamente la del arte original; solo cambian encuadre y resolucion.

Uso:
    python tool/gen_logo.py
    dart run flutter_launcher_icons   # para reconstruir los iconos de plataforma
"""
import os

from PIL import Image

SIZE = 1024
SUPERSAMPLE = 4
THRESHOLD = 128

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "tool", "brand", "attra_logo_source.png")
OUT_DIR = os.path.join(ROOT, "assets", "images")


def mark_mask() -> tuple[Image.Image, float]:
    """Silueta de la marca recortada, y que fraccion del lienzo ocupaba."""
    src = Image.open(SOURCE).convert("L")
    mask = src.point(lambda p: 255 if p > THRESHOLD else 0, mode="L")
    box = mask.getbbox()
    if box is None:
        raise SystemExit("El arte original no tiene marca blanca detectable.")
    cropped = mask.crop(box)
    # Fraccion del lienzo que ocupaba la marca en el original: se conserva para
    # que el encuadre se vea igual que el arte de partida.
    width_ratio = cropped.width / src.width
    height_ratio = cropped.height / src.height
    return cropped, max(width_ratio, height_ratio)


def render(size: int) -> Image.Image:
    """Marca blanca con alfa, cuadrada y antialiaseada, a `size` px."""
    cropped, ratio = mark_mask()
    big = size * SUPERSAMPLE
    target = int(big * ratio)

    # Se escala la SILUETA (no la imagen con fondo) manteniendo su relacion de
    # aspecto: escalar a un cuadrado deformaria la marca.
    scale = target / max(cropped.width, cropped.height)
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.LANCZOS,
    )
    # Re-umbralizar tras el escalado: deja el borde limpio antes de reducir, y
    # es la reduccion final la que aporta el antialiasing.
    resized = resized.point(lambda p: 255 if p > THRESHOLD else 0, mode="L")

    canvas = Image.new("L", (big, big), 0)
    canvas.paste(
        resized,
        ((big - resized.width) // 2, (big - resized.height) // 2),
    )
    alpha = canvas.resize((size, size), Image.LANCZOS)

    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    mark = render(SIZE)

    # Marca con transparencia: para pintarla sobre cualquier fondo (splash).
    transparent = os.path.join(OUT_DIR, "attra_mark.png")
    mark.save(transparent, "PNG")
    print(f"OK {transparent}")

    # Icono de app: fondo NEGRO solido. iOS no admite alfa en el icono.
    solid_path = os.path.join(OUT_DIR, "app_logo.png")
    solid = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    solid.paste(mark, (0, 0), mark)
    solid.save(solid_path, "PNG")
    print(f"OK {solid_path}")


if __name__ == "__main__":
    main()
