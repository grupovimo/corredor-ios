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

if __name__ == '__main__':
    globals()[sys.argv[1]](*sys.argv[2:])
