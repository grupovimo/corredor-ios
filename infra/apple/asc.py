"""Cliente mínimo de la API de App Store Connect con la clave de equipo (asc.env).

Uso: asc.py capacidades <bundle> [CAPACIDAD…] | perfiles_corredor <cert_id> <dir_salida> | grupos <app> | grupo_equipo <app> <email> <nombre> <apellido> | builds <app>
"""
import base64, os, sys, time, json, secrets, subprocess
import jwt, requests

env = {}
for linea in open(os.path.expanduser('~/Trabajo/vimo/credenciales-apple/asc.env')):
    linea = linea.strip()
    if linea and not linea.startswith('#') and '=' in linea:
        k, v = linea.split('=', 1)
        env[k.strip().removeprefix('export ').strip()] = v.strip().strip('"').strip("'")
clave = open(os.path.expanduser(env['ASC_KEY_PATH'])).read()

def token():
    ahora = int(time.time())
    return jwt.encode({'iss': env['ASC_ISSUER_ID'], 'iat': ahora, 'exp': ahora + 1100, 'aud': 'appstoreconnect-v1'},
                      clave, algorithm='ES256', headers={'kid': env['ASC_KEY_ID'], 'typ': 'JWT'})

def api(metodo, ruta, cuerpo=None):
    r = requests.request(metodo, 'https://api.appstoreconnect.apple.com' + ruta,
                         headers={'Authorization': 'Bearer ' + token()}, json=cuerpo, timeout=60)
    if r.status_code >= 400:
        sys.exit(f'{metodo} {ruta}: {r.status_code} {r.text[:600]}')
    return r.json() if r.text else {}

def certificados():
    for c in api('GET', '/v1/certificates?limit=50')['data']:
        a = c['attributes']
        print(c['id'], a['certificateType'], a.get('displayName'), a.get('name'), a.get('expirationDate'))

def perfiles():
    for p in api('GET', '/v1/profiles?limit=50')['data']:
        a = p['attributes']
        print(p['id'], a['profileType'], a['name'], a['profileState'], a.get('expirationDate'))

def bundle(identificador):
    d = api('GET', f'/v1/bundleIds?filter[identifier]={identificador}')['data']
    return [b for b in d if b['attributes']['identifier'] == identificador][0]['id']


def bundle_o_crear(identificador, nombre):
    d = api('GET', f'/v1/bundleIds?filter[identifier]={identificador}')['data']
    d = [b for b in d if b['attributes']['identifier'] == identificador]
    if d:
        return d[0]['id']
    b = api('POST', '/v1/bundleIds', {'data': {'type': 'bundleIds',
        'attributes': {'identifier': identificador, 'name': nombre, 'platform': 'IOS'}}})
    print('bundle creado', identificador)
    return b['data']['id']

def capacidades(identificador, *activar):
    """Las capacidades del App ID; con nombres (PUSH_NOTIFICATIONS, ASSOCIATED_DOMAINS…) activa las que falten."""
    bid = bundle(identificador)
    tiene = {c['attributes']['capabilityType'] for c in api('GET', f'/v1/bundleIds/{bid}/bundleIdCapabilities')['data']}
    for c in activar:
        if c not in tiene:
            api('POST', '/v1/bundleIdCapabilities', {'data': {'type': 'bundleIdCapabilities', 'attributes': {'capabilityType': c},
                'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bid}}}}})
            print('activada', c)
            tiene.add(c)
    print(identificador, sorted(tiene))

def perfiles_corredor(cert_id, salida):
    """Perfiles App Store de la app y de los widgets, con el certificado de distribución que ya existe."""
    os.makedirs(salida, mode=0o700, exist_ok=True)
    for ident, nombre in (('ar.com.corredor.app', 'Corredor'), ('ar.com.corredor.app.Widgets', 'Corredor Widgets')):
        bid = bundle_o_crear(ident, nombre)
        p = api('POST', '/v1/profiles', {'data': {'type': 'profiles',
            'attributes': {'name': f'{ident} App Store', 'profileType': 'IOS_APP_STORE'},
            'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bid}},
                              'certificates': {'data': [{'type': 'certificates', 'id': cert_id}]}}}})
        ruta = os.path.join(salida, f'{ident}.mobileprovision')
        open(ruta, 'wb').write(base64.b64decode(p['data']['attributes']['profileContent']))
        os.chmod(ruta, 0o600)
        print('perfil', p['data']['id'], ident)

def grupos(app_id):
    for g in api('GET', f'/v1/apps/{app_id}/betaGroups')['data']:
        a = g['attributes']
        print(g['id'], a['name'], 'interno' if a.get('isInternalGroup') else 'externo', 'todos' if a.get('hasAccessToAllBuilds') else '')
        for t in api('GET', f"/v1/betaGroups/{g['id']}/betaTesters")['data']:
            print('   tester', t['attributes'].get('email'))

def grupo_equipo(app_id, email, nombre, apellido):
    g = api('POST', '/v1/betaGroups', {'data': {'type': 'betaGroups',
        'attributes': {'name': 'Equipo', 'isInternalGroup': True, 'hasAccessToAllBuilds': True},
        'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})
    gid = g['data']['id']
    api('POST', '/v1/betaTesters', {'data': {'type': 'betaTesters',
        'attributes': {'email': email, 'firstName': nombre, 'lastName': apellido},
        'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': gid}]}}}})
    print('grupo', gid, 'con', email)

def builds(app_id):
    for b in api('GET', f'/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5')['data']:
        a = b['attributes']
        print(b['id'], a['version'], a['processingState'], a['uploadedDate'])

# Suscripciones de Corredor (planes por inmobiliaria). Sólo en la Argentina (la tienda cobra en USD),
# con 14 días gratis la primera vez. Idempotente: lo que ya existe se deja.
PLANES = [  # producto, nombre, período, nivel (1 = el más alto), USD, descripción
    ('ar.com.corredor.app.equipo.anio', 'Equipo anual', 'ONE_YEAR', 1, '949.99', 'Personas sin tope, consorcios, temporada e informes.'),
    ('ar.com.corredor.app.equipo.mes', 'Equipo mensual', 'ONE_MONTH', 1, '94.99', 'Personas sin tope, consorcios, temporada e informes.'),
    ('ar.com.corredor.app.profesional.anio', 'Profesional anual', 'ONE_YEAR', 2, '449.99', 'Hasta 5 personas, alquileres, portales e IA.'),
    ('ar.com.corredor.app.profesional.mes', 'Profesional mensual', 'ONE_MONTH', 2, '44.99', 'Hasta 5 personas, alquileres, portales e IA.'),
    ('ar.com.corredor.app.inicial.anio', 'Inicial anual', 'ONE_YEAR', 3, '189.99', 'Para 1 persona: cartera, agenda, web y WhatsApp.'),
    ('ar.com.corredor.app.inicial.mes', 'Inicial mensual', 'ONE_MONTH', 3, '18.99', 'Para 1 persona: cartera, agenda, web y WhatsApp.'),
]

def rel(tipo, id):
    return {'data': {'type': tipo, 'id': id}}

def suscripciones(app_id, avisos_url='https://api.corredor.com.ar/publico/apple/avisos'):
    app = api('GET', f'/v1/apps/{app_id}')['data']['attributes']
    locale = app.get('primaryLocale') or 'es-MX'
    print('idioma principal', locale)
    grupos = api('GET', f'/v1/apps/{app_id}/subscriptionGroups?limit=50')['data']
    g = next((x for x in grupos if x['attributes']['referenceName'] == 'Corredor'), None)
    if not g:
        g = api('POST', '/v1/subscriptionGroups', {'data': {'type': 'subscriptionGroups', 'attributes': {'referenceName': 'Corredor'},
            'relationships': {'app': rel('apps', app_id)}}})['data']
        api('POST', '/v1/subscriptionGroupLocalizations', {'data': {'type': 'subscriptionGroupLocalizations',
            'attributes': {'name': 'Planes de Corredor', 'locale': locale}, 'relationships': {'subscriptionGroup': rel('subscriptionGroups', g['id'])}}})
        print('grupo creado', g['id'])
    existentes = {x['attributes']['productId']: x for x in api('GET', f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50")['data']}
    for pid, nombre, periodo, nivel, usd, desc in PLANES:
        sub = existentes.get(pid)
        if not sub:
            sub = api('POST', '/v1/subscriptions', {'data': {'type': 'subscriptions', 'attributes': {
                'name': nombre, 'productId': pid, 'subscriptionPeriod': periodo, 'groupLevel': nivel, 'familySharable': False,
                'reviewNote': 'Plan de Corredor para una inmobiliaria. Se compra en la app, en Más › Tu plan.'},
                'relationships': {'group': rel('subscriptionGroups', g['id'])}}})['data']
            print('creada', pid)
        sid = sub['id']
        if not api('GET', f'/v1/subscriptions/{sid}/subscriptionLocalizations')['data']:
            api('POST', '/v1/subscriptionLocalizations', {'data': {'type': 'subscriptionLocalizations',
                'attributes': {'name': 'Corredor ' + nombre, 'locale': locale, 'description': desc},
                'relationships': {'subscription': rel('subscriptions', sid)}}})
        r = requests.get(f'https://api.appstoreconnect.apple.com/v1/subscriptions/{sid}/subscriptionAvailability',
                         headers={'Authorization': 'Bearer ' + token()}, timeout=60)
        if r.status_code == 404 or not r.json().get('data'):
            api('POST', '/v1/subscriptionAvailabilities', {'data': {'type': 'subscriptionAvailabilities',
                'attributes': {'availableInNewTerritories': False},
                'relationships': {'subscription': rel('subscriptions', sid), 'availableTerritories': {'data': [{'type': 'territories', 'id': 'ARG'}]}}}})
        if not api('GET', f'/v1/subscriptions/{sid}/prices?limit=5')['data']:
            puntos = api('GET', f'/v1/subscriptions/{sid}/pricePoints?filter[territory]=ARG&limit=8000')['data']
            punto = min(puntos, key=lambda x: abs(float(x['attributes']['customerPrice']) - float(usd)))
            api('POST', '/v1/subscriptionPrices', {'data': {'type': 'subscriptionPrices', 'attributes': {'preserveCurrentPrice': False},
                'relationships': {'subscription': rel('subscriptions', sid), 'subscriptionPricePoint': rel('subscriptionPricePoints', punto['id']),
                                  'territory': rel('territories', 'ARG')}}})
            print(pid, 'precio', punto['attributes']['customerPrice'])
        if not api('GET', f'/v1/subscriptions/{sid}/introductoryOffers?limit=5')['data']:
            api('POST', '/v1/subscriptionIntroductoryOffers', {'data': {'type': 'subscriptionIntroductoryOffers',
                'attributes': {'duration': 'TWO_WEEKS', 'offerMode': 'FREE_TRIAL', 'numberOfPeriods': 1},
                'relationships': {'subscription': rel('subscriptions', sid), 'territory': rel('territories', 'ARG')}}})
            print(pid, '14 días gratis')
        print(pid, api('GET', f'/v1/subscriptions/{sid}')['data']['attributes']['state'])
    # Los avisos del App Store (Server Notifications V2), producción y sandbox.
    api('PATCH', f'/v1/apps/{app_id}', {'data': {'type': 'apps', 'id': app_id, 'attributes': {
        'subscriptionStatusUrl': avisos_url, 'subscriptionStatusUrlVersion': 'V2',
        'subscriptionStatusUrlForSandbox': avisos_url, 'subscriptionStatusUrlVersionForSandbox': 'V2'}}})
    print('avisos', avisos_url)

def captura_revision(app_id, archivo):
    """La captura para la revisión de cada suscripción (la piden para pasar de MISSING_METADATA)."""
    import hashlib
    datos = open(archivo, 'rb').read()
    g = next(x for x in api('GET', f'/v1/apps/{app_id}/subscriptionGroups?limit=50')['data'] if x['attributes']['referenceName'] == 'Corredor')
    for sub in api('GET', f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50")['data']:
        sid = sub['id']
        r = requests.get(f'https://api.appstoreconnect.apple.com/v1/subscriptions/{sid}/appStoreReviewScreenshot',
                         headers={'Authorization': 'Bearer ' + token()}, timeout=60)
        if r.status_code == 200 and r.json().get('data'):
            print(sub['attributes']['productId'], 'ya tiene captura'); continue
        c = api('POST', '/v1/subscriptionAppStoreReviewScreenshots', {'data': {'type': 'subscriptionAppStoreReviewScreenshots',
            'attributes': {'fileName': os.path.basename(archivo), 'fileSize': len(datos)},
            'relationships': {'subscription': rel('subscriptions', sid)}}})['data']
        for op in c['attributes']['uploadOperations']:
            parte = datos[op['offset']:op['offset'] + op['length']]
            requests.request(op['method'], op['url'], data=parte,
                             headers={h['name']: h['value'] for h in op['requestHeaders']}, timeout=120).raise_for_status()
        api('PATCH', f"/v1/subscriptionAppStoreReviewScreenshots/{c['id']}", {'data': {'type': 'subscriptionAppStoreReviewScreenshots',
            'id': c['id'], 'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(datos).hexdigest()}}})
        print(sub['attributes']['productId'], 'captura subida')
    time.sleep(5)
    for sub in api('GET', f"/v1/subscriptionGroups/{g['id']}/subscriptions?limit=50")['data']:
        print(sub['attributes']['productId'], sub['attributes']['state'])

if __name__ == '__main__':
    globals()[sys.argv[1]](*sys.argv[2:])
