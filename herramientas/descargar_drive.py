"""Descarga todas las fotos de una carpeta pública de Google Drive.

gdown solo lista las primeras 50 de una carpeta; la vista embebida de Drive
las lista todas, así que se leen los ids de ahí y se bajan una por una.
Uso: python3 descargar_drive.py <enlace de la carpeta> <destino>
"""
import concurrent.futures
import os
import re
import subprocess
import sys
import time
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
        ), timeout=60
    ).read().decode("utf-8", "replace")
    archivos = re.findall(r'href="https://drive\.google\.com/file/d/([\w-]+)/[^"]*"[^>]*>.*?flip-entry-title">([^<]+)<', pagina, re.S)
    subcarpetas = re.findall(r'href="https://drive\.google\.com/drive/folders/([\w-]+)"[^>]*>.*?flip-entry-title">([^<]+)<', pagina, re.S)
    resultado = [(i, os.path.join(ruta, n)) for i, n in archivos]
    for i, n in subcarpetas:
        resultado += listar(i, os.path.join(ruta, n))
    return resultado


lista = listar(carpeta, "")
print(f"{len(lista)} archivos en la carpeta", flush=True)
for _, nombre in lista[:10]:
    print("  ", nombre)
if not lista:
    print("La vista embebida no listó nada; intento con gdown --folder", flush=True)
    subprocess.run(["gdown", "--folder", enlace, "-O", destino, "--remaining-ok"], check=True, timeout=1800)
    sys.exit(0)


def bajar(par):
    """Direct download with curl: a time limit per photo, and Drive's warning
    page (for large files) skipped with confirm=t."""
    id_archivo, nombre = par
    plano = re.sub(r"[^\w.-]", "_", nombre.replace(os.sep, "_"))
    salida = os.path.join(destino, plano)
    if os.path.exists(salida) and os.path.getsize(salida) > 10_000:
        return nombre, "ya estaba"
    url = f"https://drive.usercontent.google.com/download?id={id_archivo}&export=download&confirm=t"
    for intento in range(3):
        r = subprocess.run(["curl", "-sSL", "--max-time", "180", "-o", salida, "-w", "%{http_code} %{content_type}", url],
                           capture_output=True, text=True)
        codigo = r.stdout.strip()
        if r.returncode == 0 and codigo.startswith("200") and "text/html" not in codigo:
            return nombre, f"ok {os.path.getsize(salida) // 1024} KB"
        time.sleep(5 * (intento + 1))
    if os.path.exists(salida):
        os.remove(salida)
    return nombre, f"FALLO {codigo} {r.stderr.strip()[:120]}"


inicio = time.time()
fallos = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as hilos:
    for n, (nombre, estado) in enumerate(hilos.map(bajar, lista), 1):
        if estado.startswith("FALLO"):
            fallos += 1
        if n % 25 == 0 or estado.startswith("FALLO") or n == len(lista):
            print(f"[{n}/{len(lista)}] {nombre}: {estado} · {int(time.time() - inicio)} s", flush=True)
print(f"Listo: {len(lista) - fallos} bajadas, {fallos} fallidas en {int(time.time() - inicio)} s")
if fallos > len(lista) // 2:
    sys.exit("Fallaron más de la mitad de las descargas")
