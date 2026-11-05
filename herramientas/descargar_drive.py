"""Descarga todas las fotos de una carpeta pública de Google Drive.

gdown solo lista las primeras 50 de una carpeta; la vista embebida de Drive
las lista todas, así que se leen los ids de ahí y se bajan una por una.
Uso: python3 descargar_drive.py <enlace de la carpeta> <destino>
"""
import os
import re
import subprocess
import sys
import urllib.request

enlace, destino = sys.argv[1], sys.argv[2]
os.makedirs(destino, exist_ok=True)
coincide = re.search(r"folders/([\w-]+)", enlace) or re.search(r"id=([\w-]+)", enlace)
if not coincide:
    sys.exit("No encontré el id de la carpeta en el enlace")
carpeta = coincide.group(1)


def listar(id_carpeta, ruta):
    pagina = urllib.request.urlopen(
        urllib.request.Request(
            f"https://drive.google.com/embeddedfolderview?id={id_carpeta}",
            headers={"User-Agent": "Mozilla/5.0"},
        )
    ).read().decode("utf-8", "replace")
    archivos = re.findall(r'href="https://drive\.google\.com/file/d/([\w-]+)/[^"]*"[^>]*>.*?flip-entry-title">([^<]+)<', pagina, re.S)
    subcarpetas = re.findall(r'href="https://drive\.google\.com/drive/folders/([\w-]+)"[^>]*>.*?flip-entry-title">([^<]+)<', pagina, re.S)
    resultado = [(i, os.path.join(ruta, n)) for i, n in archivos]
    for i, n in subcarpetas:
        resultado += listar(i, os.path.join(ruta, n))
    return resultado


lista = listar(carpeta, "")
print(f"{len(lista)} archivos en la carpeta")
if not lista:
    print("La vista embebida no listó nada; intento con gdown --folder")
    subprocess.run(["gdown", "--folder", enlace, "-O", destino, "--remaining-ok"], check=True)
    sys.exit(0)
for n, (id_archivo, nombre) in enumerate(lista, 1):
    plano = re.sub(r"[^\w.-]", "_", nombre.replace(os.sep, "_"))
    salida = os.path.join(destino, plano)
    if os.path.exists(salida):
        continue
    print(f"[{n}/{len(lista)}] {nombre}", flush=True)
    subprocess.run(["gdown", "--quiet", id_archivo, "-O", salida], check=False)
