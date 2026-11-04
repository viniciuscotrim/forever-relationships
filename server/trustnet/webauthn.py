"""Minimal WebAuthn (passkeys) for a single-admin dashboard.

Registration and authentication with platform authenticators (Touch ID / Face ID
passkeys stored in Apple Passwords and synced by the Apple Account).
Implements: CBOR decoding (the subset WebAuthn uses), authenticator data
parsing, COSE EC2/P-256 keys and ES256 signature verification. User
verification (biometrics) is REQUIRED. Attestation is not used ("none"): the
trust anchor is the one-time setup link, not the device vendor.
"""
import base64
import hashlib
import json
import struct

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec

FLAG_UP = 0x01   # user present
FLAG_UV = 0x04   # user verified (biometrics / device passcode)
FLAG_AT = 0x40   # attested credential data included


class WebAuthnError(Exception):
    pass


def b64url_decode(s):
    s = s.encode("ascii") if isinstance(s, str) else s
    return base64.urlsafe_b64decode(s + b"=" * (-len(s) % 4))


def b64url_encode(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")


# --------------------------------------------------------------------------- CBOR
def cbor_decode(data):
    value, offset = _cbor_item(data, 0)
    return value, offset


def _cbor_len(data, offset, info):
    if info < 24:
        return info, offset
    size = {24: 1, 25: 2, 26: 4, 27: 8}.get(info)
    if size is None:
        raise WebAuthnError("unsupported CBOR length")
    return int.from_bytes(data[offset:offset + size], "big"), offset + size


def _cbor_item(data, offset):
    if offset >= len(data):
        raise WebAuthnError("truncated CBOR")
    initial = data[offset]
    major, info = initial >> 5, initial & 0x1F
    offset += 1
    if major == 7:
        if info == 20:
            return False, offset
        if info == 21:
            return True, offset
        if info == 22:
            return None, offset
        raise WebAuthnError("unsupported CBOR simple value")
    n, offset = _cbor_len(data, offset, info)
    if major == 0:
        return n, offset
    if major == 1:
        return -1 - n, offset
    if major == 2:
        return bytes(data[offset:offset + n]), offset + n
    if major == 3:
        return data[offset:offset + n].decode("utf-8"), offset + n
    if major == 4:
        out = []
        for _ in range(n):
            v, offset = _cbor_item(data, offset)
            out.append(v)
        return out, offset
    if major == 5:
        out = {}
        for _ in range(n):
            k, offset = _cbor_item(data, offset)
            v, offset = _cbor_item(data, offset)
            out[k] = v
        return out, offset
    raise WebAuthnError("unsupported CBOR major type %d" % major)


# --------------------------------------------------------------------------- authenticator data
def parse_auth_data(ad):
    if len(ad) < 37:
        raise WebAuthnError("authenticator data too short")
    out = {"rpIdHash": ad[:32], "flags": ad[32], "signCount": struct.unpack(">I", ad[33:37])[0]}
    if out["flags"] & FLAG_AT:
        if len(ad) < 55:
            raise WebAuthnError("attested credential data truncated")
        cred_len = struct.unpack(">H", ad[53:55])[0]
        out["aaguid"] = ad[37:53]
        out["credentialId"] = ad[55:55 + cred_len]
        out["coseKey"], _ = cbor_decode(ad[55 + cred_len:])
    return out


def cose_to_public_key(cose):
    # COSE_Key: 1 kty (2 = EC2), 3 alg (-7 = ES256), -1 crv (1 = P-256), -2 x, -3 y
    if cose.get(1) != 2 or cose.get(3) != -7 or cose.get(-1) != 1:
        raise WebAuthnError("only ES256 / P-256 passkeys are supported")
    x, y = cose[-2], cose[-3]
    return ec.EllipticCurvePublicNumbers(int.from_bytes(x, "big"), int.from_bytes(y, "big"), ec.SECP256R1()).public_key()


def public_key_bytes(cose):
    """Uncompressed point 0x04||x||y, for storage."""
    return b"\x04" + cose[-2] + cose[-3]


def public_key_from_bytes(raw):
    return ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)


# --------------------------------------------------------------------------- ceremonies
def _check_client_data(client_data_json, expected_type, challenge, origin):
    try:
        cd = json.loads(client_data_json.decode("utf-8"))
    except ValueError:
        raise WebAuthnError("bad clientDataJSON")
    if cd.get("type") != expected_type:
        raise WebAuthnError("wrong ceremony type")
    if cd.get("challenge") != b64url_encode(challenge):
        raise WebAuthnError("challenge mismatch")
    if cd.get("origin") != origin:
        raise WebAuthnError("origin mismatch: %r" % cd.get("origin"))
    if cd.get("crossOrigin"):
        raise WebAuthnError("cross-origin not allowed")
    return cd


def _check_flags(auth, rp_id):
    if auth["rpIdHash"] != hashlib.sha256(rp_id.encode("utf-8")).digest():
        raise WebAuthnError("rpId mismatch")
    if not auth["flags"] & FLAG_UP:
        raise WebAuthnError("user not present")
    if not auth["flags"] & FLAG_UV:
        raise WebAuthnError("user verification (Touch ID / Face ID) required")


def verify_registration(credential, challenge, origin, rp_id):
    """credential: the JSON the browser sends (base64url fields).
    Returns {credentialId, publicKey (bytes), signCount}."""
    resp = credential.get("response") or {}
    client_data = b64url_decode(resp.get("clientDataJSON", ""))
    _check_client_data(client_data, "webauthn.create", challenge, origin)
    att, _ = cbor_decode(b64url_decode(resp.get("attestationObject", "")))
    if not isinstance(att, dict) or "authData" not in att:
        raise WebAuthnError("bad attestation object")
    auth = parse_auth_data(att["authData"])
    _check_flags(auth, rp_id)
    if "coseKey" not in auth:
        raise WebAuthnError("no credential in attestation")
    if b64url_decode(credential.get("rawId", "")) != auth["credentialId"]:
        raise WebAuthnError("credential id mismatch")
    cose_to_public_key(auth["coseKey"])  # validates the key
    return {"credentialId": auth["credentialId"], "publicKey": public_key_bytes(auth["coseKey"]),
            "signCount": auth["signCount"]}


def verify_assertion(credential, challenge, origin, rp_id, public_key_raw, stored_sign_count):
    """Returns the new signCount. Raises WebAuthnError on any failure."""
    resp = credential.get("response") or {}
    client_data = b64url_decode(resp.get("clientDataJSON", ""))
    _check_client_data(client_data, "webauthn.get", challenge, origin)
    auth_data = b64url_decode(resp.get("authenticatorData", ""))
    auth = parse_auth_data(auth_data)
    _check_flags(auth, rp_id)
    signature = b64url_decode(resp.get("signature", ""))
    try:
        public_key_from_bytes(public_key_raw).verify(
            signature, auth_data + hashlib.sha256(client_data).digest(), ec.ECDSA(hashes.SHA256()))
    except (InvalidSignature, ValueError):
        raise WebAuthnError("bad signature")
    # synced passkeys (iCloud Keychain) report signCount 0; only enforce when counting
    if auth["signCount"] and stored_sign_count and auth["signCount"] <= stored_sign_count:
        raise WebAuthnError("sign count did not increase (cloned authenticator?)")
    return auth["signCount"]
