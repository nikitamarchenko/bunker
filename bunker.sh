#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

function bunker_create_infra()
{
  export VIRTUALBOX_MEMORY_SIZE=2000
  export VIRTUALBOX_CPU_COUNT=2
  export VIRTUALBOX_DISK_SIZE=10000

  docker-machine create -d virtualbox \
  --engine-opt="cluster-store=consul://INFRA:8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  --engine-insecure-registry="INFRA:5000" \
  node.infra.dc0.00

  docker-machine ssh node.infra.dc0.00 \
  "sudo sed -i s/INFRA/$(docker-machine ip node.infra.dc0.00)/ \
  /var/lib/boot2docker/profile && \
  sudo /etc/init.d/docker restart"

  docker $(docker-machine config node.infra.dc0.00) run \
  -d --restart=always --name docker_registry_00 \
  -v `pwd`/data:/var/lib/registry \
  -p $(docker-machine ip node.infra.dc0.00):5000:5000 \
  registry:2

  docker $(docker-machine config node.infra.dc0.00) pull progrium/consul && \
  docker $(docker-machine config node.infra.dc0.00) tag progrium/consul \
  $(docker-machine ip node.infra.dc0.00):5000/consul && \
  docker $(docker-machine config node.infra.dc0.00) push \
  $(docker-machine ip node.infra.dc0.00):5000/consul && \
  docker $(docker-machine config node.infra.dc0.00) rmi progrium/consul

  docker $(docker-machine config node.infra.dc0.00) run -d \
  --restart=always --name "docker_consul_kv_00" \
  -p 8500:8500 \
  $(docker-machine ip node.infra.dc0.00):5000/consul -server -bootstrap-expect 1

  docker $(docker-machine config node.infra.dc0.00) run -d \
  --restart=always --name "swarm-agent" \
  -p 2375:2375 \
  swarm join --advertise $(docker-machine ip node.infra.dc0.00):2376 \
  consul://$(docker-machine ip node.infra.dc0.00):8500
}

function bunker_setup_ubuntu()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  cd "$SCRIPT_DIR"/ubuntu

  docker $(docker-machine config node.infra.dc0.00) build \
  -t ubuntu:bunker .
  cd -

  docker $(docker-machine config node.infra.dc0.00) \
  tag -f ubuntu:bunker $(docker-machine ip node.infra.dc0.00):5000/ubuntu && \
  docker $(docker-machine config node.infra.dc0.00) \
  push $(docker-machine ip node.infra.dc0.00):5000/ubuntu && \
  docker $(docker-machine config node.infra.dc0.00) rmi ubuntu:bunker
}

function bunker_shell()
{
  docker run -it --rm \
  --net private \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
  --dns=8.8.8.8 \
  --dns-search=service.consul \
  $(docker-machine ip node.infra.dc0.00):5000/ubuntu
}


function bunker_create_swarm_master()
{
  export VIRTUALBOX_MEMORY_SIZE=1000
  export VIRTUALBOX_CPU_COUNT=1
  export VIRTUALBOX_DISK_SIZE=10000

  docker-machine create \
  -d virtualbox \
  --swarm --swarm-image="swarm" --swarm-master \
  --swarm-discovery="consul://$(docker-machine ip node.infra.dc0.00):8500" \
  --engine-opt="cluster-store=consul://$(docker-machine ip node.infra.dc0.00):8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  --engine-insecure-registry="$(docker-machine ip node.infra.dc0.00):5000" \
  node.swarm.dc0.00
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  docker network create --driver overlay \
  --subnet=10.0.0.0/16 \
  --ip-range=10.0.0.0/24 \
  private
}

function bunker_create_swarm_slave()
{
  export VIRTUALBOX_MEMORY_SIZE=1000
  export VIRTUALBOX_CPU_COUNT=1
  export VIRTUALBOX_DISK_SIZE=10000

  docker-machine create \
  -d virtualbox \
  --swarm --swarm-image="swarm" --swarm \
  --swarm-discovery="consul://$(docker-machine ip node.infra.dc0.00):8500" \
  --engine-opt="cluster-store=consul://$(docker-machine ip node.infra.dc0.00):8500" \
  --engine-opt="cluster-advertise=eth1:2376" \
  --engine-insecure-registry="$(docker-machine ip node.infra.dc0.00):5000" \
  node.swarm.dc0.01
}

function bunker_setup_consul()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  docker run -d \
  --env="constraint:node==node.swarm.dc0.00" \
  --name docker_consul_dns_00 \
  --net=private \
  $(docker-machine ip node.infra.dc0.00):5000/consul \
  -server -bootstrap-expect 2
  docker run -d \
  --env="constraint:node==node.swarm.dc0.01" \
  --name docker_consul_dns_01 \
  --net=private \
  $(docker-machine ip node.infra.dc0.00):5000/consul \
  -server \
  -join $(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00)
}


function bunker_setup_registrator()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  cd "$SCRIPT_DIR"/registrator

  docker $(docker-machine config node.infra.dc0.00) build \
  --no-cache --force-rm=true -t registrator .

  docker $(docker-machine config node.infra.dc0.00) \
  tag registrator $(docker-machine ip node.infra.dc0.00):5000/registrator && \
  docker $(docker-machine config node.infra.dc0.00) \
  push $(docker-machine ip node.infra.dc0.00):5000/registrator && \
  docker $(docker-machine config node.infra.dc0.00) rmi registrator

  docker run -d \
  --name=docker_registrator_00 \
  --env="constraint:node==node.infra.dc0.00" \
  --net=private \
  --volume=/var/run/docker.sock:/tmp/docker.sock \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
  $(docker-machine ip node.infra.dc0.00):5000/registrator \
  -internal \
  -overlay-net private \
  consul://consul.service.consul:8500

  docker run -d \
  --name=docker_registrator_01 \
  --env="constraint:node==node.swarm.dc0.00" \
  --net=private \
  --volume=/var/run/docker.sock:/tmp/docker.sock \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
  $(docker-machine ip node.infra.dc0.00):5000/registrator \
  -internal \
  -overlay-net private \
  consul://consul.service.consul:8500

  docker run -d \
  --name=docker_registrator_02 \
  --env="constraint:node==node.swarm.dc0.01" \
  --net=private \
  --volume=/var/run/docker.sock:/tmp/docker.sock \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00) \
  --dns=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01) \
  $(docker-machine ip node.infra.dc0.00):5000/registrator \
  -internal \
  -overlay-net private \
  consul://consul.service.consul:8500

  cd -
}

function bunker_setup_elasticsearch()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
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
}

function bunker_setup_logstash()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  cd "$SCRIPT_DIR"/logstash

  docker $(docker-machine config node.infra.dc0.00) build \
  -t logstash:bunker .

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

  cd -
}

function bunker_setup_kibana()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
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
}

function bunker_setup_logspout()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  cd "$SCRIPT_DIR"/logspout

  docker $(docker-machine config node.infra.dc0.00) build \
  -t logspout:bunker .

  cd -

  docker $(docker-machine config node.infra.dc0.00) tag logspout:bunker \
  $(docker-machine ip node.infra.dc0.00):5000/logspout && \
  docker $(docker-machine config node.infra.dc0.00) push \
  $(docker-machine ip node.infra.dc0.00):5000/logspout

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

  docker run -d \
  --name="docker_logspout_01" \
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

  docker run -d \
  --name="docker_logspout_02" \
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
}

function bunker_setup_prometheus()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  cd "$SCRIPT_DIR"/prometheus

  docker $(docker-machine config node.infra.dc0.00) build \
  -t prometheus:bunker .

  cd -

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
}

function bunker_setup_cadvisor()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)

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

}

function bunker_setup_shooter()
{
  eval $(docker-machine env --swarm node.swarm.dc0.00)
  cd "$SCRIPT_DIR"/shooter

  docker $(docker-machine config node.infra.dc0.00) build \
  -t shooter .

  cd -
  docker $(docker-machine config node.infra.dc0.00) tag -f shooter:latest \
  $(docker-machine ip node.infra.dc0.00):5000/shooter && \
  docker $(docker-machine config node.infra.dc0.00) push \
  $(docker-machine ip node.infra.dc0.00):5000/shooter
}

export BUNKER_REGISTRY=$(docker-machine ip node.infra.dc0.00):5000
export BUNKER_DNS_0=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_00)
export BUNKER_DNS_1=$(docker inspect --format '{{ .NetworkSettings.Networks.private.IPAddress }}' docker_consul_dns_01)

function bunker_run_shooter()
{
  cd "$SCRIPT_DIR"/shooter
  docker-compose up -d
  docker-compose scale shooter=3
  cd -
}


function bunker_deploy()
{
  bunker_create_infra
  bunker_create_swarm_master
  bunker_create_swarm_slave
  bunker_setup_consul
  bunker_setup_registrator
  bunker_setup_elasticsearch
  bunker_setup_logstash
  bunker_setup_kibana
  bunker_setup_logspout
  bunker_setup_prometheus
  bunker_setup_cadvisor
}
