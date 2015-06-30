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
RUN        wget -q -O - http://packages.elasticsearch.org/GPG-KEY-elasticsearch | apt-key add - && \
           echo 'deb http://packages.elasticsearch.org/logstash/1.5/debian stable main' > /etc/apt/sources.list.d/logstash.list && \
           apt-get update -qq && \
           apt-get install -qq logstash && \
           apt-get clean && rm -rf /var/lib/apt/lists/* && \
           mkdir -p /etc/logstash/conf.d

# Copy and install patched version of gelf-rb/logstash-output-gelf
RUN        cd /opt && \
           git clone https://github.com/edefaria/patch-gelf-output-logstash && \
           /opt/patch-gelf-output-logstash/update-gelf.sh

VOLUME     [ "/etc/logstash/conf.d" ]

COPY       patterns /opt/logstash/patterns
#COPY       conf.d        /opt/conf.d
COPY       logstash.conf /opt/logstash.conf
COPY       logstash.crt  /opt/logstash-forwarder/logstash.crt
COPY       logstash.key  /opt/logstash-forwarder/logstash.key

ADD        start.sh /usr/local/bin/start.sh
CMD        [ "/usr/local/bin/start.sh" ]
