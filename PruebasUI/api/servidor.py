"""La API de Corredor para los recorridos de XCUITest en GitHub.

Sirve las respuestas grabadas de la API real (respuestas.json, las genera `api/internal/demo` en el repo
privado: siembra una inmobiliaria completa y pide cada ruta que usa la app). Con los mismos ids, así que
ir de una lista a una ficha anda igual que en producción. Las escrituras responden como la API (201 con
la entidad, 204 al borrar); el vivo (/v1/eventos) manda «listo» y latidos.

Lo que la app pide y no está grabado queda en faltantes.log: el CI lo imprime para sumarlo a la grabación.

    python3 PruebasUI/api/servidor.py 8787
"""
import json
import os
import struct
import sys
import threading
import time
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

AQUI = os.path.dirname(os.path.abspath(__file__))
PUERTO = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
BASE = f"http://127.0.0.1:{PUERTO}"

with open(os.path.join(AQUI, "respuestas.json"), encoding="utf-8") as f:
    GRABADO = json.load(f)
RESPUESTAS = {
    r["ruta"]: json.dumps(r["cuerpo"], ensure_ascii=False).replace("http://api.test", BASE)
    for r in GRABADO["respuestas"]
}
FALTANTES = os.path.join(AQUI, "faltantes.log")
_lock = threading.Lock()


def faltante(linea):
    with _lock:
        with open(FALTANTES, "a", encoding="utf-8") as f:
            f.write(linea + "\n")


def png():
    """Una foto de 4×3 gris claro: para las fotos de las propiedades y los archivos."""
    w, h = 4, 3
    filas = b"".join(b"\x00" + bytes([0xD9, 0xD4, 0xC8]) * w for _ in range(h))

    def bloque(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + bloque(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + bloque(b"IDAT", zlib.compress(filas)) + bloque(b"IEND", b""))


FOTO = png()


def buscar(ruta, consulta):
    """Primero con la consulta (documentos?propiedad=…), después sin ella."""
    if consulta and f"{ruta}?{consulta}" in RESPUESTAS:
        return RESPUESTAS[f"{ruta}?{consulta}"]
    if ruta in RESPUESTAS:
        return RESPUESTAS[ruta]
    # Con otra consulta grabada para la misma ruta (p. ej. otra propiedad): la que haya.
    for k, v in RESPUESTAS.items():
        if k.split("?")[0] == ruta:
            return v
    return None


def entidad_para(ruta):
    """Lo que devuelve un alta o un cambio: la entidad grabada de esa ruta o el primer elemento de la lista."""
    cuerpo = buscar(ruta, "")
    if cuerpo is None:
        return json.dumps({"id": "nuevo-1"})
    datos = json.loads(cuerpo)
    if isinstance(datos, list):
        return json.dumps(datos[0] if datos else {"id": "nuevo-1"}, ensure_ascii=False)
    return cuerpo


class Manejador(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def enviar(self, estado, cuerpo=b"", tipo="application/json"):
        if isinstance(cuerpo, str):
            cuerpo = cuerpo.encode("utf-8")
        self.send_response(estado)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def do_GET(self):
        u = urlsplit(self.path)
        if not u.path.startswith("/v1/"):
            return self.enviar(200, FOTO, "image/png")
        if u.path == "/v1/eventos":
            return self.vivo()
        if "/contenido" in u.path or u.path.startswith("/v1/archivos/"):
            return self.enviar(200, FOTO, "image/png")
        cuerpo = buscar(u.path, u.query)
        if cuerpo is None:
            faltante(f"GET {self.path}")
            return self.enviar(404, json.dumps({"title": "No lo encontramos", "status": 404, "code": "no_encontrado"}))
        self.enviar(200, cuerpo)

    def escritura(self):
        u = urlsplit(self.path)
        largo = int(self.headers.get("Content-Length") or 0)
        if largo:
            self.rfile.read(largo)
        if self.command == "DELETE":
            return self.enviar(204)
        if u.path == "/v1/archivos" or u.path.endswith("/archivo"):
            return self.enviar(201, json.dumps({"id": "archivo-1", "url": f"{BASE}/archivos/archivo-1.png", "tipo": "image/png"}))
        if u.path.startswith("/v1/auth/") or u.path.startswith("/v1/push"):
            return self.enviar(200, buscar("/v1/auth/sesion", "") or "{}")
        if self.command == "POST":
            # Una acción sobre una entidad (/mover, /cobros…) o un alta en una colección.
            base = u.path.rsplit("/", 1)[0] if buscar(u.path, "") is None else u.path
            return self.enviar(201, entidad_para(u.path) if buscar(u.path, "") is not None else entidad_para(base))
        return self.enviar(200, entidad_para(u.path))

    do_POST = do_PUT = do_PATCH = do_DELETE = escritura

    def vivo(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(b"retry: 3000\nevent: listo\ndata: {}\n\n")
            self.wfile.flush()
            while True:
                time.sleep(15)
                self.wfile.write(b": latido\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass


if __name__ == "__main__":
    open(FALTANTES, "w").close()
    print(f"API de prueba en {BASE} con {len(RESPUESTAS)} rutas", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PUERTO), Manejador).serve_forever()
