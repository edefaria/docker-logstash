## docker-logstash : Docker image with logstash 2.X + TCP/TLS gelf support

* [DockerFile](https://github.com/edefaria/docker-logstash)
* [Logstash](https://github.com/elastic/logstash)
* [Logstash-output-gelf](https://github.com/edefaria/logstash-output-gelf)
* [Logstash-input-gelf](https://github.com/edefaria/logstash-input-gelf)
* [Logstash-codec-gelf](https://github.com/edefaria/logstash-codec-gelf)
* [Gelf-rb](https://github.com/edefaria/gelf-rb)

### Services
  * logstash
  * input syslog (tcp port 1514 by default or port 5514)
  * input syslog (tcp with tls port 10514 by default)
  * input lumberjack/logstash-forwaders (tcp with tls port 5043 by default)
  * input json (tcp port 5001 by default)
  * input gelf (udp port 12200 by default)

### Build

```
$ git clone https://github.com/edefaria/patch-gelf-output-logstash.git
$ cd docker-logstash
$ docker build -t docker-logstash .
```

### RUN

```
docker run -p 1514:1514 -p 5043:5043 -p 5001:5001 -p 10514:10514 -p 12200:12200/udp -e TIMEZONE=Europe/Paris --name docker-logstash docker-logstash
```

### Usage
INPUT Possible :
```
Port 1514 is required if you use syslog.
Port 10514 is required if you use syslog with tls on tcp.
Port 5043 is required if you use logstash-forwader/lumberjack.
Port 12200/udp is required if you use gelf (UDP only).
Port 5001 is required if you use json on TCP.
```

To customise the configuration you can mount the configuration folder with a volume.
Add docker args: "-v /etc/logstash/conf.d/:/etc/logstash/conf.d/".
If you do that, please set environment variable KEEP_CONFIG=true for keeping at startup your current configuration.

Environment variable:
```
DEBUG=1 => launch logstash in DEBUG mode
TIMEZONE=Europe/Paris => time zone of the docker, please set to the same timezone as your syslog server
GELF_OUTPUT_HOST => Host for gelf output
GELF_OUTPUT_PORT => Port for gelf output
GELF_OUTPUT_PROTOCOL => Protocol (TCP/UDP) for gelf output
GELF_OUTPUT_TLS => TLS (true/false) for gelf output
GELF_STATIC_FIELDS => list of context values to add to your stream like "app:test2,foo:bar2"
```

### Redirect to logstash
  * rsyslog

Edit: /etc/rsyslog.d/60-forward.conf
```
$template raw,"<%pri%>%timestamp:::date-rfc3339% %hostname% %syslogtag%%msg%\n"
*.* @@$HOSTNAME:1514;raw
```

  * rsyslog-gnutls

Edit: /etc/rsyslog.d/60-forward.conf
```
$DefaultNetstreamDriver gtls # use gtls netstream driver
$ActionSendStreamDriverMode 1 # require TLS for the connection
$ActionSendStreamDriverAuthMode anon # server is NOT authenticated
$template GRAYLOGRFC5424,"<%PRI%>%PROTOCOL-VERSION% %timestamp:::date-rfc3339% %HOSTNAME% %app-name% %procid% %STRUCTURED-DATA% %msg%\n"
*.* @@(o)$HOSTNAME:10514;GRAYLOGRFC5424
```

  * syslog-ng

Edit:  /etc/syslog-ng/conf.d/22-forward.conf
```
destination remote_log_server { tcp("$HOSTNAME" port(1514)); };
log { source(src); destination(remote_log_server); };
```

  * logstash-forwaders

Edit: /path_installation_of_logstash-forwarder/logstash-forwarder.conf
```
{
  "network": {
    "servers": [ "$HOSTNAME:5043" ],
    "ssl key": "/etc/pki/tls/private/logstash-forwarder.key",
    "ssl ca": "/etc/pki/tls/certs/logstash-forwarder.crt",
    "ssl certificate": "/etc/pki/tls/certs/logstash-forwarder.crt",
    "timeout": 15
  },

  "files": [
    {
      "paths": [ "/var/log/syslog" ],
      "fields": { "type": "syslog" }
    }
  ]
}
```

  * logstash with gelf (UPD)

Edit: /etc/logstash.conf
```
output {
  gelf {
    hosts => [ "$HOSTNAME" ]
    port => 12200
  }
}
```

### Edit logstash configuration

By default "logstash.conf" is generated with:
* filter "foo" on all input to add a specific field to your stream
* output gelf modified by docker environment variable.

Initial configuration: logstash.conf
```
input {
  tcp {
    port => 5001
    type => foo
  }
  syslog {
    port => 1514
    type => foo
  }
  gelf {
    port =>12200
    type => foo
  }
  lumberjack {
   port => 5043
   type => foo
   ssl_certificate => "/opt/logstash-forwarder/logstash-forwarder.crt"
   ssl_key => "/opt/logstash-forwarder/logstash-forwarder.key"
  }
}

filter {
  if [type] == "foo" {
    mutate {
      #add_field => [ "foo", "bar" ]
    }
  }
}

output {
  gelf {
    host => "localhost"
    port => 12202
    protocol => "tcp"
    tls => "true"
  }
  stdout {}
}
```

### TLS note

"*.crt" file and "*.key" file must be the same for client (output program like lumberjack) and server (input service like lumberjack inside the docker image). By default the image has these 2 files "logstash.crt" and "logstash.key" at the root of DockerFile. Please replace these files by your certificate before building your docker image to add it into the image.
