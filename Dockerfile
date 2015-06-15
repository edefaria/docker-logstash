FROM       ubuntu:vivid

MAINTAINER Edward De Faria <edward.de-faria@ovh.net>

ENV        DEBIAN_FRONTEND noninteractive

# Install Java 7
RUN        apt-get update -qq && \
           apt-get install -qq curl software-properties-common software-properties-common > /dev/null && \
           apt-get update -qq && \
           add-apt-repository -y ppa:webupd8team/java && \
           apt-get update -qq && \
           echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections && \
           echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections && \
           apt-get install -qq oracle-java7-installer oracle-java7-set-default > /dev/null && \
           apt-get clean && rm -rf /var/lib/apt/lists/* && \
           rm -rf /var/cache/oracle-jdk7-installer
ENV 	   JAVA_HOME /usr/lib/jvm/java-7-oracle

# Install logstash dependencies 
RUN        apt-get update -qq && \
           apt-get install -qq ruby ruby-dev jruby make rake git ca-certificates ca-certificates-java > /dev/null && \ 
           apt-get clean && rm -rf /var/lib/apt/lists/*

# Install logstash
ENV        LOGSTASH_VERSION 1.5.1
RUN        cd /tmp && wget -q https://github.com/elastic/logstash/archive/v${LOGSTASH_VERSION}.tar.gz && \
           tar -xzf v${LOGSTASH_VERSION}.tar.gz -C /opt && \
           mv /opt/logstash-${LOGSTASH_VERSION} /opt/logstash && \
           rm -f v${LOGSTASH_VERSION}.tar.gz && \
           cd /opt/logstash  && \
           rake bootstrap >/dev/null && \
           mkdir -p /etc/logstash/conf.d

# Install patched version of gelf-rb/logstash-output-gelf
RUN        cd /opt && \
           git clone https://github.com/edefaria/patch-gelf-output-logstash && \
           /opt/patch-gelf-output-logstash/update-gelf.sh

VOLUME     [ "/etc/logstash/conf.d" ]

COPY       grok-patterns /opt/logstash/patterns/grok-patterns
#COPY       conf.d        /opt/conf.d
COPY       logstash.conf /opt/logstash.conf
COPY       logstash.crt  /opt/logstash-forwarder/logstash.crt
COPY       logstash.key  /opt/logstash-forwarder/logstash.key

ADD        start.sh /usr/local/bin/start.sh
CMD        [ "/usr/local/bin/start.sh" ]
