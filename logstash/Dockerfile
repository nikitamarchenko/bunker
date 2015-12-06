FROM logstash
MAINTAINER Nikita Marchenko <nikita.marchenko@gmail.com>

COPY . /
CMD ["logstash", "agent", "-f", "/etc/logstash/conf.d"]
EXPOSE 5000
