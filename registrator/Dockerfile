FROM golang:1.5.1
MAINTAINER Nikita Marchenko <nikita.marchenko@gmail.com>

COPY build.bash /go/src/
ENTRYPOINT ["/bin/registrator"]
RUN /go/src/build.bash
