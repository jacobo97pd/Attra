"""Tests offline de tool/seed_identity_matrix.py.

No tocan la red ni Firebase: comprueban la parte que de verdad puede fallar en
silencio, que es la COBERTURA. Un perfil mal repartido no da error, simplemente
deja a alguien sin feed, y eso no se ve hasta que una persona con esa identidad
se instala la app.

    python -m unittest tool.test_seed_identity_matrix
"""

import unittest

from tool import seed_identity_matrix as sim


class TestCobertura(unittest.TestCase):
    """La matriz cubre todo lo que el onboarding deja elegir."""

    @classmethod
    def setUpClass(cls):
        cls.fichas = sim.construir()

    def test_estan_las_ocho_identidades(self):
        generos = {f["gender"] for f in self.fichas}
        esperados = {g for g, _, _ in sim.IDENTIDADES}
        self.assertEqual(generos, esperados)
        self.assertEqual(len(esperados), 8)

    def test_estan_las_diez_orientaciones(self):
        # Las diez de _orientationOptions en onboarding_screen.dart.
        esperadas = {
            "straight", "gay", "lesbian", "bisexual", "pansexual",
            "asexual", "demisexual", "queer", "questioning", "other",
        }
        sembradas = {o for f in self.fichas for o in f["orientation"]}
        self.assertEqual(sembradas, esperadas)

    def test_estan_los_cuatro_modos(self):
        modos = {f["intentMode"] for f in self.fichas}
        self.assertEqual(modos, {"dating", "friends", "both", "groups"})

    def test_ninguna_identidad_se_queda_sin_feed(self):
        """Para cada (a quien busco, que soy) tiene que haber alguien.

        Es la comprobacion que justifica el script entero: el filtro de genero
        es bidireccional, asi que no basta con que exista un perfil de la
        casilla que busco, tiene que buscarme a mi tambien.
        """
        for busco in sim.CASILLAS:
            for soy in sim.CASILLAS:
                hay = [
                    f for f in self.fichas
                    if sim.CASILLA_DE.get(f["gender"]) in (busco, "any")
                    and soy in f["interestedIn"]
                    and f["intentMode"] in ("dating", "both")
                ]
                self.assertTrue(
                    hay,
                    f"nadie para quien busca {busco} y se declara {soy}",
                )

    def test_toda_identidad_declarable_aparece_para_alguien(self):
        """Las ocho identidades, no solo las tres casillas."""
        for identidad, _, _ in sim.IDENTIDADES:
            perfiles = [f for f in self.fichas if f["gender"] == identidad]
            self.assertTrue(perfiles, f"sin perfiles de {identidad}")
            casilla = sim.CASILLA_DE[identidad]
            self.assertIn(casilla, sim.CASILLAS + ["any"])

    def test_interestedIn_solo_usa_casillas_validas(self):
        """`interestedIn` solo admite las tres casillas del onboarding.

        Sembrar 'trans_woman' ahi no fallaria al escribir, pero seria un valor
        que la app no sabe producir ni volver a leer desde su propio selector.
        """
        for f in self.fichas:
            for valor in f["interestedIn"]:
                self.assertIn(valor, sim.CASILLAS, f"{f['escenario']}")


class TestFichas(unittest.TestCase):
    """Los documentos que se escriben tienen la forma que lee la app."""

    @classmethod
    def setUpClass(cls):
        cls.completas = sim.completar(sim.construir(), {"h": [], "m": []})

    def test_pais_canonizable_a_espana(self):
        # canonCountry (feed_filter.dart) reconoce 'España'/'Espana'/'Spain'.
        # Con modo viajes el filtro de pais NO es permisivo: un pais que no
        # canonice deja el feed vacio sin ningun aviso.
        for f in self.completas:
            doc = sim.documento(f, "https://ejemplo/foto.jpg")
            self.assertIn(doc["currentCountryName"].lower(),
                          ("españa", "espana", "spain"))

    def test_campos_que_el_feed_necesita_si_o_si(self):
        for f in self.completas:
            doc = sim.documento(f, "https://ejemplo/foto.jpg")
            # isBot tiene que ser booleano: la consulta es where('isBot',==,true)
            # y una cadena "true" haria el perfil invisible.
            self.assertIs(doc["isBot"], True)
            self.assertTrue(doc["displayName"])
            self.assertTrue(doc["photoUrl"])
            self.assertTrue(doc["geo"]["lat"])
            self.assertTrue(doc["currentCity"])

    def test_ids_unicos(self):
        ids = [f["uid"] for f in self.completas]
        self.assertEqual(len(ids), len(set(ids)))

    def test_ids_con_el_prefijo_que_sabe_borrar_clean(self):
        for f in self.completas:
            self.assertTrue(f["uid"].startswith(sim.PREFIJO))

    def test_prompts_completos(self):
        """Un prompt a medias desaparece en silencio (profile_state.dart)."""
        for f in self.completas:
            doc = sim.documento(f, "https://ejemplo/foto.jpg")
            for prompt in doc["profilePrompts"]:
                self.assertTrue(prompt["question"])
                self.assertTrue(prompt["answer"])
                self.assertIs(prompt["isActive"], True)

    def test_edades_dentro_de_lo_razonable(self):
        edades = [f["edad"] for f in self.completas]
        self.assertGreaterEqual(min(edades), 18)
        self.assertLessEqual(max(edades), 99)
        # Repartidas, no todas en la misma franja.
        self.assertGreater(max(edades) - min(edades), 30)

    def test_nombre_coherente_con_la_casilla(self):
        """Una ficha de mujer no puede llamarse con un nombre de la lista de
        hombres: se lee como un mock roto, no como diversidad."""
        for f in self.completas:
            casilla = sim.CASILLA_DE.get(f["gender"], "any")
            if casilla == "female":
                self.assertIn(f["displayName"], sim.NOMBRES["female"])
            elif casilla == "male":
                self.assertIn(f["displayName"], sim.NOMBRES["male"])
            else:
                self.assertIn(f["displayName"], sim.NOMBRES["neutro"])


class TestFotos(unittest.TestCase):
    def test_una_cara_por_perfil(self):
        """Dos perfiles con la misma foto se parecen al 100% entre si y la
        prueba de la IA visual deja de medir nada."""
        caras = {
            "h": [f"h{i:02d}.jpg" for i in range(1, 21)],
            "m": [f"m{i:02d}.jpg" for i in range(1, 21)],
        }
        completas = sim.completar(sim.construir(), caras)
        usadas = [f["cara"] for f in completas if f["cara"]]
        self.assertEqual(len(usadas), len(completas))
        self.assertEqual(len(usadas), len(set(usadas)), "hay caras repetidas")

    def test_sin_caras_no_revienta(self):
        """Sin el directorio de caras el script sigue pudiendo sembrar con
        fotos de respaldo, en vez de fallar a medias."""
        completas = sim.completar(sim.construir(), {"h": [], "m": []})
        self.assertTrue(all(f["cara"] is None for f in completas))


if __name__ == "__main__":
    unittest.main()
