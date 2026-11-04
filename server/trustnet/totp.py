"""RFC 6238 TOTP (6 digits, 30 s, SHA-1): the code format Apple Passwords generates."""
import base64
import hashlib
import hmac
import secrets
import struct
import urllib.parse


def new_secret():
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def _key(secret_b32):
    s = secret_b32.upper()
    return base64.b32decode(s + "=" * (-len(s) % 8))


def code_at(secret_b32, t, step=30, digits=6):
    counter = int(t // step)
    mac = hmac.new(_key(secret_b32), struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = mac[-1] & 0x0F
    value = (struct.unpack(">I", mac[offset:offset + 4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return str(value).zfill(digits)


def verify(secret_b32, code, t, window=1, last_used_step=None):
    """Returns the matched time step, or None. Accepts +-window steps of clock
    drift and refuses to reuse a step that was already accepted (replay)."""
    code = (code or "").strip().replace(" ", "")
    if not (len(code) == 6 and code.isdigit()):
        return None
    now_step = int(t // 30)
    for step in range(now_step - window, now_step + window + 1):
        if last_used_step is not None and step <= last_used_step:
            continue
        if hmac.compare_digest(code_at(secret_b32, step * 30), code):
            return step
    return None


def otpauth_uri(secret_b32, account, issuer="Trust Advisor"):
    label = urllib.parse.quote("%s:%s" % (issuer, account))
    q = urllib.parse.urlencode({"secret": secret_b32, "issuer": issuer, "algorithm": "SHA1", "digits": 6, "period": 30})
    return "otpauth://totp/%s?%s" % (label, q)
