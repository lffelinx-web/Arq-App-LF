"""Reduce una malla texturizada (OBJ) a cierto número de triángulos, conservando la textura.
Uso: python3 reducir.py <entrada.obj> <salida.obj> <triangulos>
"""
import sys

import pymeshlab

entrada, salida, objetivo = sys.argv[1], sys.argv[2], int(sys.argv[3])
ms = pymeshlab.MeshSet()
ms.load_new_mesh(entrada)
malla = ms.current_mesh()
print(f"Original: {malla.vertex_number()} vértices, {malla.face_number()} triángulos", flush=True)
if malla.face_number() > objetivo:
    ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=objetivo, preservenormal=True)
malla = ms.current_mesh()
print(f"Reducida: {malla.vertex_number()} vértices, {malla.face_number()} triángulos", flush=True)
ms.save_current_mesh(salida)
