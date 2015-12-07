import socket
import sys
import random

import zerorpc
import gevent

# from gevent import monkey
# monkey.patch_all()

HOST_NAME = socket.gethostname()


class Shooter(object):

    def hit(self, name):
        sys.stdout.write('{} : hit from {}\n'.format(HOST_NAME, name))
        return HOST_NAME


def server():
    s = zerorpc.Server(Shooter())
    s.bind('tcp://0.0.0.0:10000')
    sys.stdout.write('server start\n')
    s.run()


def aim():
    while True:
        client = zerorpc.Client()
        _, _, hosts = socket.gethostbyname_ex('shooter')
        host = random.choice(hosts)
        client.connect('tcp://{}:10000'.format(host))
        sys.stdout.write('{} : shoot to {}\n'.format(HOST_NAME, client.hit(HOST_NAME)))
        client.close()
        gevent.sleep(5)


if __name__ == '__main__':
    gevent.joinall(map(gevent.spawn, [server, aim]))
