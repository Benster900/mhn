from flask import Flask
from flask.ext.sqlalchemy import SQLAlchemy
from flask.ext.security import Security, SQLAlchemyUserDatastore
from flask.ext.security.utils import encrypt_password as encrypt


db = SQLAlchemy()
# After defining `db`, import auth models due to
# circular dependency.
from mhn.auth.models import User, Role
user_datastore = SQLAlchemyUserDatastore(db, User, Role)


mhn = Flask(__name__)
mhn.config.from_object('config')

# Registering app on db instance.
db.init_app(mhn)

# Setup flask-security for auth.
Security(mhn, user_datastore)

# Registering blueprints.
from mhn.api.views import api
mhn.register_blueprint(api)

from mhn.ui.views import ui
mhn.register_blueprint(ui)

from mhn.auth.views import auth
mhn.register_blueprint(auth)

# Trigger templatetag register.
from mhn.common.templatetags import format_date
mhn.jinja_env.filters['fdate'] = format_date

from mhn.auth.contextprocessors import user_ctx
mhn.context_processor(user_ctx)

from mhn.common.contextprocessors import config_ctx
mhn.context_processor(config_ctx)

import logging
from logging.handlers import RotatingFileHandler

mhn.logger.setLevel(logging.INFO)
formatter = logging.Formatter(
      '%(asctime)s -  %(pathname)s - %(message)s')
handler = RotatingFileHandler(
        mhn.config['LOG_FILE_PATH'], maxBytes=10240, backupCount=5)
handler.setLevel(logging.INFO)
handler.setFormatter(formatter)
mhn.logger.addHandler(handler)
if mhn.config['DEBUG']:
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    console.setFormatter(formatter)
    mhn.logger.addHandler(console)


def create_clean_db():
    """
    Use from a python shell to create a fresh database.
    """
    mhn.test_request_context().push()
    db.create_all()
    # Creating superuser entry.
    superuser = user_datastore.create_user(
            email=mhn.config.get('SUPERUSER_EMAIL'),
            password=encrypt(mhn.config.get('SUPERUSER_PASSWORD')))
    adminrole = user_datastore.create_role(name='admin', description='')
    user_datastore.add_role_to_user(superuser, adminrole)

    from os import path

    from mhn.api.models import DeployScript, RuleSource
    from mhn.tasks.rules import fetch_sources
    # Creating a initial deploy script.
    # Reading initial deploy script should be: ../../scripts/mhndeploy.sh
    deploypath = path.abspath('../scripts/mhndeploy.sh')
    with open(deploypath, 'r') as deployfile:
        initdeploy = DeployScript()
        initdeploy.script = deployfile.read()
        initdeploy.notes = 'Initial deploy script'
        initdeploy.user = superuser
        db.session.add(initdeploy)

    # Creating an initial rule source.
    rulesrc = RuleSource()
    rulesrc.name = 'Emerging Threats'
    rulesrc.uri = 'http://rules.emergingthreats.net/open/snort-2.9.0/emerging-all.rules'
    rulesrc.name = 'Default rules source'
    db.session.add(rulesrc)
    db.session.commit()
    fetch_sources()