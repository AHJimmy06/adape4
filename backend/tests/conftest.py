"""Local-only integration fixtures; never accept an ambient cloud database URL."""
import os
from pathlib import Path
from uuid import uuid4

import pytest


@pytest.fixture(scope='module')
def isolated_database():
    dsn = os.getenv('AEROTECH_TEST_DSN')
    if not dsn:
        pytest.skip('Set AEROTECH_TEST_DSN to an explicitly isolated loopback PostgreSQL server.')
    import psycopg
    from psycopg.conninfo import conninfo_to_dict, make_conninfo
    config = conninfo_to_dict(dsn)
    if config.get('host') not in ('127.0.0.1', 'localhost', '::1'):
        pytest.fail('Integration tests refuse non-loopback database destinations.')
    database = 'aerotech_test_' + uuid4().hex
    with psycopg.connect(dsn, autocommit=True) as admin:
        from psycopg import sql
        admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(database)))
    config['dbname'] = database
    local = make_conninfo(**config)
    with psycopg.connect(local, autocommit=True) as conn:
        conn.execute(Path('database/schema.sql').read_text(encoding='utf-8'))
        # schema.sql includes 008 in fresh installs after implementation closes.
        if not conn.execute("select to_regclass('public.at_vuelos')").fetchone()[0]:
            conn.execute(Path('database/migrations/008_sistema_integral.sql').read_text(encoding='utf-8'))
    yield local
    print('Disposable test database retained for parent cleanup: ' + database)


@pytest.fixture
def sql_connection(isolated_database):
    import psycopg
    with psycopg.connect(isolated_database) as conn:
        yield conn
        conn.rollback()
