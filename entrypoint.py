import os
import base64
import logging.handlers
import pathlib
import socket
import subprocess

import yaml

from privacyidea.app import create_app
from privacyidea.cli.pimanage.pi_setup import (create_pgp_keys)
from privacyidea.lib.security.default import DefaultSecurityModule
from privacyidea.lib.auth import create_db_admin
from privacyidea.models import db
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

app = create_app(config_name='production',config_file='/privacyidea/etc/pi.cfg')

os.chdir('/privacyidea/')

# Update database schema, if set
PI_UPDATE = os.environ.get('PI_UPDATE', False)

# Create enckey
if not os.path.exists('/privacyidea/etc/persistent/enckey') or os.path.getsize('/privacyidea/etc/persistent/enckey') == 0:
    if 'PI_ENCKEY' in os.environ and not os.path.exists('/privacyidea/etc/persistent/enckey'):
        with open('/privacyidea/etc/persistent/enckey', 'wb') as f:
            f.write(base64.b64decode(os.environ['PI_ENCKEY']))
        os.chmod('/privacyidea/etc/persistent/enckey', 0o400)
    else:
     enc_file = pathlib.Path('/privacyidea/etc/persistent/enckey')

    with open(enc_file, "wb") as f:
        f.write(DefaultSecurityModule.random(96))
        enc_file.chmod(0o400)

# Create audit keys if not exists
priv_key_path = os.environ.get('PI_AUDIT_KEY_PRIVATE', '/privacyidea/etc/persistent/private.pem')
pub_key_path = os.environ.get('PI_AUDIT_KEY_PUBLIC', '/privacyidea/etc/persistent/public.pem')

if not os.path.exists('/privacyidea/etc/persistent/private.pem'):
    priv_key = pathlib.Path(priv_key_path)
    
    if not priv_key.is_file():
        new_key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
            backend=default_backend()
        )
        priv_pem = new_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption()
        )
        with open(priv_key, "wb") as f:
            f.write(priv_pem)

        pub_key = pathlib.Path(pub_key_path)
        public_key = new_key.public_key()
        pub_pem = public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )
        with open(pub_key, "wb") as f:
            f.write(pub_pem)
                    
# Bootstrap database
if os.path.exists('/privacyidea/etc/persistent/enckey') and not os.path.exists('/privacyidea/etc/persistent/dbcreated'):
    with app.app_context():
        dbcreate = db.create_all()
    open('/privacyidea/etc/persistent/dbcreated', 'w').close()

with app.app_context():
    create_db_admin(os.environ.get('PI_ADMIN', 'admin'), 'email',os.environ.get('PI_ADMIN_PASS', 'admin'))

# Dev-only: import resolver.json (resolvers/realms/policies) on first run.
# Gated on PI_SEED_RESOLVERS=true (set only in application-dev.env) plus a flag
# file so re-runs don't duplicate or overwrite admin tweaks.
if os.environ.get('PI_SEED_RESOLVERS', '').lower() == 'true':
    resolver_json = '/privacyidea/etc/persistent/resolver.json'
    resolver_flag = '/privacyidea/etc/persistent/resolver_imported'
    if os.path.exists(resolver_json) and not os.path.exists(resolver_flag):
        result = subprocess.run(
            ['/privacyidea/venv/bin/pi-manage', 'config', 'import', '-i', resolver_json],
            check=False,
        )
        if result.returncode == 0:
            pathlib.Path(resolver_flag).touch()

# ---------------------------------------------------------------------------
# Optional syslog handler — inject into logging.cfg before gunicorn starts
# ---------------------------------------------------------------------------
_syslog_enabled = os.environ.get('PI_SYSLOG_ENABLED', '').lower() in ('true', '1', 'yes')
_syslog_host = os.environ.get('PI_SYSLOG_HOST', '')

if _syslog_enabled and _syslog_host:
    _log_cfg_path = '/privacyidea/etc/logging.cfg'
    _log_cfg_out = '/privacyidea/etc/persistent/logging_runtime.cfg'

    with open(_log_cfg_path) as _f:
        _log_cfg = yaml.safe_load(_f)

    _syslog_port = int(os.environ.get('PI_SYSLOG_PORT', '514'))
    _syslog_proto = os.environ.get('PI_SYSLOG_PROTO', 'udp').lower()
    _syslog_facility = os.environ.get('PI_SYSLOG_FACILITY', 'local1')
    _syslog_tag = os.environ.get('PI_SYSLOG_TAG', 'privacyidea')
    _syslog_level = os.environ.get('PI_SYSLOG_LEVEL', 'INFO').upper()
    _socktype = 'ext://socket.SOCK_STREAM' if _syslog_proto == 'tcp' else 'ext://socket.SOCK_DGRAM'

    _fac_num = logging.handlers.SysLogHandler.facility_names.get(
        _syslog_facility, logging.handlers.SysLogHandler.LOG_LOCAL1)

    _log_cfg.setdefault('handlers', {})['syslog'] = {
        'class': 'logging.handlers.SysLogHandler',
        'address': [_syslog_host, _syslog_port],
        'socktype': _socktype,
        'facility': _fac_num,
        'level': _syslog_level,
        'formatter': 'syslog',
    }
    _log_cfg.setdefault('formatters', {})['syslog'] = {
        'format': _syslog_tag + ': [%(levelname)s] %(name)s: %(message)s',
    }

    # Add syslog handler to root logger only (privacyidea logger propagates
    # to root, so adding to both would duplicate every message).
    _root = _log_cfg.setdefault('root', {})
    _root_handlers = _root.get('handlers', [])
    if 'syslog' not in _root_handlers:
        _root_handlers.append('syslog')
        _root['handlers'] = _root_handlers

    with open(_log_cfg_out, 'w') as _f:
        yaml.dump(_log_cfg, _f, default_flow_style=False)

    os.environ['PI_LOGCONFIG'] = _log_cfg_out
    print(f"[entrypoint] syslog enabled: {_syslog_tag} -> {_syslog_host}:{_syslog_port}/{_syslog_proto} "
          f"facility={_syslog_facility} level={_syslog_level}")

# Run the app using gunicorn WSGI HTTP server
cmd = [ "python",
    "-m", "gunicorn",
    "-w", "1",
    "-b", os.environ['PI_ADDRESS']+":"+os.environ['PI_PORT'],
    "privacyidea.app:create_app(config_name='production',config_file='/privacyidea/etc/pi.cfg')"
]

os.execvp('python', cmd)
