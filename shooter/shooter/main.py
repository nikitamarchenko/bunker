import socket
import sys
import os
import random
import logging
import logstash

import zerorpc
import gevent

from zerorpc import exceptions as zerorpc_exceptions

SHOOTER_ID = socket.gethostname()
IP = socket.gethostbyname(socket.gethostname())

LOG = logging.getLogger()
LOG.setLevel(logging.INFO)
LOG.addHandler(logstash.LogstashHandler('logstash', 5000, version=1))

LOG_EXTRA = {
    'container_id': socket.gethostname(),
    'service': 'shooter'
}

VERSION = '0.0.0.4'

class Shooter(object):

    def hit(self, name):
        LOG.info('{}: hit from {}'.format(SHOOTER_ID, name), extra=LOG_EXTRA)
        return SHOOTER_ID


def server():
    s = zerorpc.Server(Shooter())
    s.bind('tcp://0.0.0.0:10000')
    LOG.info('{}: server start. version: {}'.format(SHOOTER_ID, VERSION),
             extra=LOG_EXTRA)
    s.run()


def aim():
    while True:
        client = zerorpc.Client()
        try:
            _, _, hosts = socket.gethostbyname_ex('shooter')
            host = random.choice([x for x in hosts if x != IP])
        except IndexError:
            LOG.warning('{} : no target'.format(SHOOTER_ID), extra=LOG_EXTRA)
            continue

        client.connect('tcp://{}:10000'.format(host))
        try:
            LOG.info('{} : shoot to {}'.format(SHOOTER_ID, client.hit(SHOOTER_ID)), extra=LOG_EXTRA)
        except zerorpc_exceptions.LostRemote:
            LOG.warning('{} : lost target'.format(SHOOTER_ID), extra=LOG_EXTRA)

        client.close()
        gevent.sleep(5)


if __name__ == '__main__':
    gevent.joinall(map(gevent.spawn, [server, aim]))
