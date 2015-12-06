## setup elasticsearch on infra node.infra.dc0.00

```
docker run -d \
--name docker_elasticsearch_00 \
--env="constraint:node==node.infra.dc0.00" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
-e 'LOGSPOUT=ignore' \
elasticsearch elasticsearch
```

## build and install logstash

```
cd bunker/logstash

docker $(docker-machine config node.infra.dc0.00) build \
-t logstash:bunker .
```

```
docker run -d \
--name docker_logstash_00 \
--env="constraint:node==node.infra.dc0.00" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
-e 'LOGSPOUT=ignore' \
logstash:bunker
```

## kibana
```
docker run -d \
--name docker_kibana_00 \
--env="constraint:node==node.infra.dc0.00" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
-e ELASTICSEARCH_URL=http://elasticsearch-9200:9200 \
-p 5601:5601 \
-e 'LOGSPOUT=ignore' \
kibana
```

## logspout

build logspout with logstash support

```
cd bunker/logspout

docker $(docker-machine config node.infra.dc0.00) build \
-t logspout:bunker .

docker $(docker-machine config node.infra.dc0.00) tag logspout:bunker \
$(docker-machine ip node.infra.dc0.00):5000/logspout && \
docker $(docker-machine config node.infra.dc0.00) push \
$(docker-machine ip node.infra.dc0.00):5000/logspout
```

install

```
docker run -d \
--name="docker_logspout_00" \
--volume=/var/run/docker.sock:/tmp/docker.sock \
--env="constraint:node==node.infra.dc0.00" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
-e 'ROUTE_URIS=logstash://logstash.service.consul:5000' \
-e 'LOGSPOUT=ignore' \
$(docker-machine ip node.infra.dc0.00):5000/logspout
```

```
docker run -it --rm \
--name="docker_logspout_00" \
--volume=/var/run/docker.sock:/tmp/docker.sock \
--env="constraint:node==node.swarm.dc0.00" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
-e 'ROUTE_URIS=logstash://logstash.service.consul:5000' \
-e 'LOGSPOUT=ignore' \
$(docker-machine ip node.infra.dc0.00):5000/logspout
```

```
docker run -it --rm \
--name="docker_logspout_00" \
--volume=/var/run/docker.sock:/tmp/docker.sock \
--env="constraint:node==node.swarm.dc0.01" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
-e 'ROUTE_URIS=logstash://logstash.service.consul:5000' \
-e 'LOGSPOUT=ignore' \
$(docker-machine ip node.infra.dc0.00):5000/logspout
```

## prometheus
```
eval $(docker-machine env --swarm node.swarm.dc0.00)
cd bunker/prometheus

docker $(docker-machine config node.infra.dc0.00) build \
-t prometheus:bunker .

docker run -d \
--name="docker_prometheus_00" \
--env="constraint:node==node.infra.dc0.00" \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
-p $(docker-machine ip node.infra.dc0.00):9090:9090 \
prometheus:bunker
```

## cadvisor
```
docker run \
--name=docker_cadvisor_00 \
--env="constraint:node==node.infra.dc0.00" \
--detach=true \
--volume=/:/rootfs:ro \
--volume=/var/run:/var/run:rw \
--volume=/sys:/sys:ro \
--volume=/var/lib/docker/:/var/lib/docker:ro \
--publish=8080:8080 \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
google/cadvisor:latest

docker run \
--name=docker_cadvisor_01 \
--env="constraint:node==node.swarm.dc0.00" \
--detach=true \
--volume=/:/rootfs:ro \
--volume=/var/run:/var/run:rw \
--volume=/sys:/sys:ro \
--volume=/var/lib/docker/:/var/lib/docker:ro \
--publish=8080:8080 \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
google/cadvisor:latest

docker run \
--name=docker_cadvisor_02 \
--env="constraint:node==node.swarm.dc0.01" \
--detach=true \
--volume=/:/rootfs:ro \
--volume=/var/run:/var/run:rw \
--volume=/sys:/sys:ro \
--volume=/var/lib/docker/:/var/lib/docker:ro \
--publish=8080:8080 \
--net private \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
--dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
--dns=8.8.8.8 \
--dns-search=service.consul \
google/cadvisor:latest
```
