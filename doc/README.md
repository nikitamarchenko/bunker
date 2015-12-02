

This is tutorial about building a Docker-based cluster with overlay network and
DNS-based service discovery and auto registration new containers.

After all steps, we get a 3 nodes cluster. The first node is infra, it's
responsibilities is providing key value storage for Swarm also it is Docker
private registry. The second node is Swarm Master - primary cloud entry
point, it is host primary Consul DNS service and Registrator. The last node is
backup node for Consul DNS service. All nodes, except infra, has Registrator on
board and linked together by overlay network which is named as 'private', so containers,
in swarm cluster, can communicate each other via "private" network using
simple naming, for example, you can connect to MySQL
`mysql --host=my_mysql_container_name --user=myname --password=mypass mydb.`

## Naming
- Nodes `node.<name>.<dc>.<index from 00>`
- Docker containers `docker_<name>_<index from 00>`
- Network `<name>` without '-'


## Infra Components
- consul in docker as kv storage
- docker image repo
- docker image builder
- TODO: swarm agent in docker

## Worker Components

- 00
  - swarm master in docker
  - consul master dns in docker on overlay net
  - custom registrator in docker on overlay net
- 01
  - swarm agent in docker
  - consul slave dns in docker on overlay net
  - custom registrator in docker on overlay net
- NN
  - swarm agent in docker
  - custom registrator in docker on overlay net

# Network
Overlay network has name private and connect all nodes

# Setup

## Infra node
create infra node
```
docker-machine create -d virtualbox node.infra.dc0.00
```
### Registry
```
docker-machine ssh node.infra.dc0.00
sudo vi /var/lib/boot2docker/profile
```
append `EXTRA_ARGS` with `--insecure-registry=<ip of node.infra.dc0.00>:5000`

node ip you can get from command `docker-machine ip node.infra.dc0.00`
```
sudo /etc/init.d/docker restart
```

create docker registry on node.infra.dc0.00
```
docker $(docker-machine config node.infra.dc0.00) run \
-d --restart=always --name docker_registry_00 \
-v `pwd`/data:/var/lib/registry \
-p $(docker-machine ip node.infra.dc0.00):5000:5000 \
registry:2
```
push consul image into docker_registry_00
```
docker $(docker-machine config node.infra.dc0.00) pull progrium/consul && \
docker $(docker-machine config node.infra.dc0.00) tag progrium/consul \
$(docker-machine ip node.infra.dc0.00):5000/consul && \
docker $(docker-machine config node.infra.dc0.00) push \
$(docker-machine ip node.infra.dc0.00):5000/consul && \
docker $(docker-machine config node.infra.dc0.00) rmi progrium/consul
```

### Consul
install consul as key\value storage on infra for swarm
```
docker $(docker-machine config node.infra.dc0.00) run -d \
--name "docker_consul_kv_00" \
-p 8500:8500 \
$(docker-machine ip node.infra.dc0.00):5000/consul -server -bootstrap-expect 1
```

## Swarm Master
create swarm master
```
docker-machine create \
-d virtualbox \
--swarm --swarm-image="swarm" --swarm-master \
--swarm-discovery="consul://$(docker-machine ip node.infra.dc0.00):8500" \
--engine-opt="cluster-store=consul://$(docker-machine ip node.infra.dc0.00):8500" \
--engine-opt="cluster-advertise=eth1:2376" \
--engine-insecure-registry="$(docker-machine ip node.infra.dc0.00):5000" \
node.swarm.dc0.00
```

switch shell on node.swarm.dc0.00 as Swarm master

**IMPORTANT: all docker commands must be executed from swarm master env**
```
eval $(docker-machine env --swarm node.swarm.dc0.00)
```

create overlay network over all swarm nodes
```
docker network create --driver overlay \
--subnet=10.0.0.0/16 \
--ip-range=10.0.0.0/24 \
private
```

## Swarm slave
create second node in cluster it will be swarm slave
```
docker-machine create \
-d virtualbox \
--swarm --swarm-image="swarm" --swarm \
--swarm-discovery="consul://$(docker-machine ip node.infra.dc0.00):8500" \
--engine-opt="cluster-store=consul://$(docker-machine ip node.infra.dc0.00):8500" \
--engine-opt="cluster-advertise=eth1:2376" \
--engine-insecure-registry="$(docker-machine ip node.infra.dc0.00):5000" \
node.swarm.dc0.01
```

## Consul dns service
create consul node.swarm.dc0.00
```
docker run -d \
--env="constraint:node==node.swarm.dc0.00" \
--name docker_consul_dns_00 \
--net=private \
$(docker-machine ip node.infra.dc0.00):5000/consul \
-server -bootstrap-expect 2
```
create consul node.swarm.dc0.01
```
docker run -d \
--env="constraint:node==node.swarm.dc0.01" \
--name docker_consul_dns_01 \
--net=private \
$(docker-machine ip node.infra.dc0.00):5000/consul \
-server \
-join $(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00)
```
check consul
```
docker logs docker_consul_dns_00 | grep joined
```
```
2015/12/01 16:55:43 [INFO] consul: member '3cd9801f1d19' joined, marking health alive
2015/12/01 16:55:43 [INFO] consul: member '138c591a661d' joined, marking health alive
```

now we have 2 dns nodes in private network
```
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00)
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01)
```

## Registrator

build custom registrator image and push to registry
```
git clone https://github.com/nikitamarchenko/bunker

cd bunker/registrator

docker $(docker-machine config node.infra.dc0.00) build \
--no-cache --force-rm=true -t registrator .

docker $(docker-machine config node.infra.dc0.00) \
tag registrator $(docker-machine ip node.infra.dc0.00):5000/registrator && \
docker $(docker-machine config node.infra.dc0.00) \
push $(docker-machine ip node.infra.dc0.00):5000/registrator && \
docker $(docker-machine config node.infra.dc0.00) rmi registrator
```

install on node.swarm.dc0.00
```
docker run -d \
--name=docker_registrator_00 \
--env="constraint:node==node.swarm.dc0.00" \
--net=private \
--volume=/var/run/docker.sock:/tmp/docker.sock \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
$(docker-machine ip node.infra.dc0.00):5000/registrator \
-internal \
-overlay-net private \
consul://consul.service.consul:8500
```
install on node.swarm.dc0.01
```
docker run -d \
--name=docker_registrator_01 \
--env="constraint:node==node.swarm.dc0.01" \
--net=private \
--volume=/var/run/docker.sock:/tmp/docker.sock \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
$(docker-machine ip node.infra.dc0.00):5000/registrator \
-internal \
-overlay-net private \
consul://consul.service.consul:8500
```


## test connectivity between 2 nodes by private network and dns services lookup.

Install 2 redis on host node.swarm.dc0.00 and node.swarm.dc0.01
```
docker run -d \
--name docker_redis_00 \
--env="constraint:node==node.swarm.dc0.00" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
redis
```

```
docker run -d \
--name docker_redis_01 \
--env="constraint:node==node.swarm.dc0.01" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
redis
```
Get Redis service ip
```
docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_redis_00
 10.0.0.6
docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_redis_01
 10.0.0.7
```
Then run busybox
```
docker run -it --rm \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
busybox
```
If we try to ping Redis we should get two IP addresses
```
/ # ping redis
PING redis (10.0.0.7): 56 data bytes
64 bytes from 10.0.0.7: seq=0 ttl=64 time=0.072 ms
64 bytes from 10.0.0.7: seq=1 ttl=64 time=0.260 ms
^C
--- redis ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.072/0.166/0.260 ms
/ # ping redis
PING redis (10.0.0.6): 56 data bytes
64 bytes from 10.0.0.6: seq=0 ttl=64 time=0.505 ms
64 bytes from 10.0.0.6: seq=1 ttl=64 time=0.433 ms
^C
--- redis ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.433/0.469/0.505 ms
```
