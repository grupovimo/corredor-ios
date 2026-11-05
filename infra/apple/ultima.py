"""Todos los testers de TestFlight, en todas las apps de la cuenta, con la última versión y nada más.

Por cada app: la build más nueva lista entra a todos los grupos (los internos con acceso a todas ya
la tienen), se manda a la revisión beta si hay grupos externos y, cuando ya la puede instalar todo el
mundo, las anteriores se vencen para que nadie se quede con una vieja. Lo corre el workflow
testflight-ultima cada media hora; también a mano: `uv run --with 'pyjwt[crypto]' --with requests
python infra/apple/ultima.py`.

Credenciales: ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_P8 (base64) en el entorno, o el asc.env de la Mac.
"""
import base64, os, sys, time
import jwt, requests

if os.environ.get('ASC_KEY_P8'):
    KID, ISS = os.environ['ASC_KEY_ID'], os.environ['ASC_ISSUER_ID']
    CLAVE = base64.b64decode(os.environ['ASC_KEY_P8']).decode()
else:
    env = {}
    for linea in open(os.path.expanduser('~/Trabajo/vimo/credenciales-apple/asc.env')):
        linea = linea.strip()
        if linea and not linea.startswith('#') and '=' in linea:
            k, v = linea.split('=', 1)
            env[k.strip().removeprefix('export ').strip()] = v.strip().strip('"').strip("'")
    KID, ISS = env['ASC_KEY_ID'], env['ASC_ISSUER_ID']
    CLAVE = open(os.path.expanduser(env['ASC_KEY_PATH'])).read()


def token():
    ahora = int(time.time())
    return jwt.encode({'iss': ISS, 'iat': ahora, 'exp': ahora + 1100, 'aud': 'appstoreconnect-v1'},
                      CLAVE, algorithm='ES256', headers={'kid': KID, 'typ': 'JWT'})


def api(metodo, ruta, cuerpo=None):
    """Devuelve (status, json); no corta: una app que falla no frena a las demás."""
    r = requests.request(metodo, 'https://api.appstoreconnect.apple.com' + ruta,
                         headers={'Authorization': 'Bearer ' + token()}, json=cuerpo, timeout=60)
    return r.status_code, (r.json() if r.text else {})


def todos(ruta):
    datos = []
    while ruta:
        st, r = api('GET', ruta)
        if st >= 400:
            raise RuntimeError(f'GET {ruta}: {st} {str(r)[:300]}')
        datos += r['data']
        siguiente = r.get('links', {}).get('next')
        ruta = siguiente.removeprefix('https://api.appstoreconnect.apple.com') if siguiente else None
    return datos


def numero(b):
    v = b['attributes']['version']
    return int(v) if v.isdigit() else -1


def una_app(app):
    nombre = app['attributes']['name']
    builds = [b for b in todos(f'/v1/builds?filter[app]={app["id"]}&limit=200')
              if not b['attributes']['expired']]
    listas = [b for b in builds if b['attributes']['processingState'] == 'VALID']
    if not listas:
        print(f'{nombre}: sin builds listas')
        return
    ultima = max(listas, key=numero)
    grupos = todos(f'/v1/betaGroups?filter[app]={app["id"]}&limit=50')
    externos = [g for g in grupos if not g['attributes']['isInternalGroup']]

    for g in grupos:
        if g['attributes']['isInternalGroup'] and g['attributes'].get('hasAccessToAllBuilds'):
            continue
        st, r = api('POST', f'/v1/betaGroups/{g["id"]}/relationships/builds',
                    {'data': [{'type': 'builds', 'id': ultima['id']}]})
        if st >= 400:
            print(f'{nombre}: no pude sumar la {numero(ultima)} a {g["attributes"]["name"]}: {st}')

    lista_para_todos = True
    if externos:
        st, det = api('GET', f'/v1/builds/{ultima["id"]}/buildBetaDetail')
        estado = det.get('data', {}).get('attributes', {}).get('externalBuildState', '')
        if estado in ('READY_FOR_BETA_SUBMISSION', 'MISSING_EXPORT_COMPLIANCE'):
            st, r = api('POST', '/v1/betaAppReviewSubmissions', {'data': {
                'type': 'betaAppReviewSubmissions',
                'relationships': {'build': {'data': {'type': 'builds', 'id': ultima['id']}}}}})
            estado = 'mandada a revisión' if st < 400 else f'revisión pendiente ({st}: otra build en revisión, reintenta solo)'
        lista_para_todos = estado in ('BETA_APPROVED', 'IN_BETA_TESTING')
        print(f'{nombre}: build {numero(ultima)} · externos {estado}')
    else:
        print(f'{nombre}: build {numero(ultima)} · sólo internos')

    if not lista_para_todos:
        return
    for b in builds:
        if numero(b) < numero(ultima):
            st, r = api('PATCH', f'/v1/builds/{b["id"]}',
                        {'data': {'type': 'builds', 'id': b['id'], 'attributes': {'expired': True}}})
            print(f'  vencida la {numero(b)}' if st < 400 else f'  no pude vencer la {numero(b)}: {st}')


def main():
    fallas = 0
    for app in todos('/v1/apps?limit=200'):
        try:
            una_app(app)
        except Exception as e:  # noqa: BLE001
            fallas += 1
            print(f'{app["attributes"]["name"]}: {e}')
    sys.exit(1 if fallas else 0)


if __name__ == '__main__':
    main()
