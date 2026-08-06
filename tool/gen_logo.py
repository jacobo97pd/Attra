"""Genera el logotipo de Attra (la marca lambda) en los tamanos que usa la app.

La marca es geometrica: una "lambda" blanca de trazo grueso sobre negro, con el
vertice arriba y las patas abiertas hasta la base. Al ser pura geometria se
genera por codigo en vez de arrastrar un PNG, asi cualquier ajuste de grosor o
proporcion se hace aqui y se regenera todo de una vez.

Uso:
    python tool/gen_logo.py

Genera:
    assets/images/app_logo.png        1024x1024, fondo negro (icono de app y splash)
    assets/images/attra_mark.png      1024x1024, fondo transparente (uso sobre color)

Tras regenerar el icono de app hay que reconstruir los iconos de plataforma:
    dart run flutter_launcher_icons
"""
import os
from PIL import Image, ImageDraw

# Trabajamos a 4x y reducimos: da bordes suaves sin depender de librerias extra.
SUPERSAMPLE = 4
SIZE = 1024

BLACK = (0, 0, 0, 255)
WHITE = (255, 255, 255, 255)

# Geometria en proporciones del lienzo (0..1), medida sobre la marca original.
APEX_X = 0.500        # vertice, centrado
APEX_Y = 0.088        # altura del vertice
BASE_Y = 0.892        # donde terminan las patas
OUTER_HALF = 0.392    # medio ancho exterior en la base
INNER_HALF = 0.252    # medio ancho interior en la base (define el grosor)


def mark_polygon(size: int) -> list[tuple[float, float]]:
    """Contorno de la lambda: exterior derecho, interior, exterior izquierdo.

    El vertice interior NO se elige a ojo: se calcula para que los bordes
    interiores sean PARALELOS a los exteriores. Si no, el trazo se ensancha
    hacia el vertice y la marca se deforma.
    """
    apex_x = APEX_X * size
    apex_y = APEX_Y * size
    base_y = BASE_Y * size
    outer_dx = OUTER_HALF * size
    inner_dx = INNER_HALF * size

    # Pendiente del borde exterior (dy/dx), replicada en el interior.
    slope = (base_y - apex_y) / outer_dx
    inner_apex_y = base_y - slope * inner_dx

    return [
        (apex_x, apex_y),                    # vertice exterior
        (apex_x + outer_dx, base_y),         # pie derecho exterior
        (apex_x + inner_dx, base_y),         # pie derecho interior
        (apex_x, inner_apex_y),              # vertice interior
        (apex_x - inner_dx, base_y),         # pie izquierdo interior
        (apex_x - outer_dx, base_y),         # pie izquierdo exterior
    ]


def render(size: int, background) -> Image.Image:
    big = size * SUPERSAMPLE
    img = Image.new("RGBA", (big, big), background)
    ImageDraw.Draw(img).polygon(mark_polygon(big), fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "assets", "images")
    os.makedirs(out_dir, exist_ok=True)

    # Icono de app y splash: fondo NEGRO solido. iOS no admite alfa en el icono.
    solid = os.path.join(out_dir, "app_logo.png")
    render(SIZE, BLACK).convert("RGB").save(solid, "PNG")
    print(f"OK {solid}")

    # Marca suelta con transparencia, para pintarla sobre cualquier fondo.
    transparent = os.path.join(out_dir, "attra_mark.png")
    render(SIZE, (0, 0, 0, 0)).save(transparent, "PNG")
    print(f"OK {transparent}")


if __name__ == "__main__":
    main()
