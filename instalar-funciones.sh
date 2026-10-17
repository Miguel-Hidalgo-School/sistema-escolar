#!/bin/bash
# Crea la carpeta con las Cloud Functions del Sistema Escolar. No despliega nada por sí solo.
set -e
mkdir -p sistema-escolar-functions/functions
cd sistema-escolar-functions
cat > functions/package.json <<'FINDELARCHIVO'
{
  "name": "sistema-escolar-functions",
  "private": true,
  "engines": { "node": "20" },
  "main": "index.js",
  "dependencies": {
    "firebase-admin": "^12.7.0",
    "firebase-functions": "^6.0.1"
  }
}
FINDELARCHIVO
cat > functions/index.js <<'FINDELARCHIVO'
/**
 * Sistema Escolar · Cloud Functions (fase 1)
 *
 * IMPORTANTE: estas funciones son NUEVAS y no cambian nada de lo que ya existe.
 * La app actual sigue funcionando igual hasta que se decida llamarlas.
 *
 * Reglas de quién puede qué (igual que hoy en la app):
 *  - Súper Administrador: está en /admins/<uid> = true.
 *  - Gestor: perfil con puedeGestionarUsuarios = true (solo crea usuarios que
 *    comparten SU espacio, nunca otro gestor).
 */
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();
const db = admin.database();
const auth = admin.auth();

const DOMINIO = '@chavarria.edu.com';
// Mientras la app siga mostrando la contraseña temporal desde el perfil
// (WhatsApp), se guarda igual que hoy. Cuando la pantalla use la contraseña que
// devuelve la función, se cambia a false y deja de guardarse en la base.
const GUARDAR_TEMPORAL = true;

const OPC = { region: 'us-central1', maxInstances: 5, cors: true };

function passwordTemporal() {
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789';
  let p = '';
  const b = crypto.randomBytes(10);
  for (let i = 0; i < 10; i++) p += a[b[i] % a.length];
  return p;
}

async function quienLlama(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Inicia sesión.');
  const uid = request.auth.uid;
  const esSuper = (await db.ref('admins/' + uid).once('value')).val() === true;
  const perfil = (await db.ref('perfiles/' + uid).once('value')).val() || null;
  const activo = !perfil || (perfil.deshabilitado !== true && perfil.eliminado !== true);
  if (!activo) throw new HttpsError('permission-denied', 'Cuenta deshabilitada.');
  const esGestor = !!(perfil && perfil.puedeGestionarUsuarios === true);
  return { uid, esSuper, esGestor, perfil };
}

function rolDe(p, esSuper) {
  if (esSuper) return 'superadmin';
  if (p && p.puedeGestionarUsuarios === true) return 'gestor';
  return 'usuario';
}

// Comprobación sin efectos: ¿quién soy para el servidor?
exports.ping = onCall(OPC, async (request) => {
  const q = await quienLlama(request);
  return { uid: q.uid, esSuperAdmin: q.esSuper, esGestor: q.esGestor, ok: true };
});

// Crea un usuario (misma lógica que hoy en usuarios.html, pero en el servidor).
exports.crearUsuario = onCall(OPC, async (request) => {
  const q = await quienLlama(request);
  if (!q.esSuper && !q.esGestor) throw new HttpsError('permission-denied', 'No puedes crear usuarios.');
  const d = request.data || {};
  const usuario = String(d.usuario || '').trim().split('@')[0].toLowerCase();
  if (!/^[a-z0-9._-]{2,40}$/.test(usuario)) throw new HttpsError('invalid-argument', 'Usuario no válido.');
  const email = usuario + DOMINIO;
  const pass = passwordTemporal();
  let rec;
  try {
    rec = await auth.createUser({ email, password: pass, displayName: String(d.nombre || '').slice(0, 80) });
  } catch (e) {
    if (e.code === 'auth/email-already-exists') throw new HttpsError('already-exists', 'Ese usuario ya existe.');
    throw new HttpsError('internal', 'No se pudo crear la cuenta.');
  }
  const espacioUid = q.esSuper ? rec.uid : ((q.perfil && q.perfil.espacioUid) || q.uid);
  const perfil = {
    email, nombre: String(d.nombre || '').slice(0, 80), telefono: String(d.telefono || '').slice(0, 30),
    correoContacto: String(d.correoContacto || '').slice(0, 120),
    mustChangePassword: true,
    creadoPor: q.uid, creadoEn: new Date().toISOString(), espacioUid,
    accesoPrimaria: !!d.accesoPrimaria, accesoSecundaria: !!d.accesoSecundaria,
    accesoCheckin: !!d.accesoCheckin, accesoBitacora: !!d.accesoBitacora,
    puedeGestionarUsuarios: q.esSuper ? !!d.puedeGestionarUsuarios : false,
    deshabilitado: false, eliminado: false
  };
  if (GUARDAR_TEMPORAL) perfil.tempPasswordActual = pass;
  const up = { ['perfiles/' + rec.uid]: perfil };
  if (!q.esSuper) up['gestores/' + q.uid + '/misUsuarios/' + rec.uid] = true;
  await db.ref().update(up);
  await auth.setCustomUserClaims(rec.uid, { espacio: espacioUid, rol: rolDe(perfil, false) });
  return { uid: rec.uid, email, passwordTemporal: pass };
});

async function puedeGestionarA(q, uid) {
  const p = (await db.ref('perfiles/' + uid).once('value')).val();
  if (!p) throw new HttpsError('not-found', 'Usuario no encontrado.');
  if (!(q.esSuper || p.creadoPor === q.uid)) throw new HttpsError('permission-denied', 'No es tu usuario.');
  return p;
}

// Restablece la contraseña: genera una temporal nueva y obliga a cambiarla.
exports.restablecerPassword = onCall(OPC, async (request) => {
  const q = await quienLlama(request);
  const uid = String((request.data || {}).uid || '');
  await puedeGestionarA(q, uid);
  const pass = passwordTemporal();
  await auth.updateUser(uid, { password: pass });
  await auth.revokeRefreshTokens(uid);
  const up = { mustChangePassword: true };
  up.tempPasswordActual = GUARDAR_TEMPORAL ? pass : null;
  await db.ref('perfiles/' + uid).update(up);
  return { uid, passwordTemporal: pass };
});

// Deshabilita / habilita de verdad (Firebase Auth) y cierra sus sesiones abiertas.
exports.deshabilitarUsuario = onCall(OPC, async (request) => {
  const q = await quienLlama(request);
  const d = request.data || {};
  const uid = String(d.uid || '');
  await puedeGestionarA(q, uid);
  const deshabilitar = d.deshabilitar !== false;
  await auth.updateUser(uid, { disabled: deshabilitar });
  if (deshabilitar) await auth.revokeRefreshTokens(uid);
  await db.ref('perfiles/' + uid).update({ deshabilitado: deshabilitar });
  return { uid, deshabilitado: deshabilitar };
});

// "Elimina": borra la cuenta de acceso, pero CONSERVA los datos de la escuela.
exports.eliminarUsuario = onCall(OPC, async (request) => {
  const q = await quienLlama(request);
  const uid = String((request.data || {}).uid || '');
  if (uid === q.uid) throw new HttpsError('failed-precondition', 'No puedes eliminarte a ti mismo.');
  const p = await puedeGestionarA(q, uid);
  if ((await db.ref('admins/' + uid).once('value')).val() === true) throw new HttpsError('failed-precondition', 'No se elimina a un Súper Administrador.');
  try { await auth.deleteUser(uid); } catch (e) { if (e.code !== 'auth/user-not-found') throw new HttpsError('internal', 'No se pudo eliminar.'); }
  await db.ref('perfiles/' + uid).update({ eliminado: true, deshabilitado: true, tempPasswordActual: null });
  return { uid, eliminado: true };
});

// Una sola vez: pone en cada cuenta existente su "espacio" y "rol" dentro del
// inicio de sesión. Solo Súper Administradores. No modifica datos ni perfiles.
exports.sincronizarClaims = onCall({ ...OPC, timeoutSeconds: 300 }, async (request) => {
  const q = await quienLlama(request);
  if (!q.esSuper) throw new HttpsError('permission-denied', 'Solo Súper Administradores.');
  const admins = (await db.ref('admins').once('value')).val() || {};
  const perfiles = (await db.ref('perfiles').once('value')).val() || {};
  const adminEspacio = (await db.ref('adminEspacio').once('value')).val() || null;
  let n = 0;
  for (const uid of Object.keys(admins)) {
    if (admins[uid] !== true) continue;
    try { await auth.setCustomUserClaims(uid, { espacio: adminEspacio || uid, rol: 'superadmin' }); n++; } catch (e) {}
  }
  for (const uid of Object.keys(perfiles)) {
    if (admins[uid] === true) continue;
    const p = perfiles[uid] || {};
    if (p.eliminado === true) continue;
    try { await auth.setCustomUserClaims(uid, { espacio: p.espacioUid || uid, rol: rolDe(p, false) }); n++; } catch (e) {}
  }
  return { actualizadas: n };
});
FINDELARCHIVO
cat > firebase.json <<'FINDELARCHIVO'
{
  "functions": [
    { "source": "functions", "codebase": "default" }
  ]
}
FINDELARCHIVO
cat > .firebaserc <<'FINDELARCHIVO'
{ "projects": { "default": "sistema-escolar-a5c31" } }
FINDELARCHIVO
echo "Listo. Ahora ejecuta: cd sistema-escolar-functions && firebase login --no-localhost"
