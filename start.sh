#!/bin/bash

DEFAULT_GELF_OUTPUT_HOST="localhost"
DEFAULT_GELF_OUTPUT_PORT="12202"
DEFAULT_GELF_OUTPUT_PROTOCOL="tcp"
DEFAULT_GELF_OUTPUT_TLS="true"

LOGSTASH_CONFIGURATION_FILE="/etc/logstash/conf.d/logstash.conf"
LOGSTASH_CONFIGURATION_FILE_TEMPLATE="/opt/logstash.conf"
LOGSTASH_CONFIGURATION_FILE_TMP="/tmp/logstash.conf"

if [ -z "${GELF_OUTPUT_HOST}" ] ; then
  echo "WARNING no environmnet variable GELF_OUTPUT_HOST is define. Use \"${DEFAULT_GELF_OUTPUT_HOST}\" by default."
  export GELF_OUTPUT_HOST="${DEFAULT_GELF_OUTPUT_HOST}"
fi

if [ -z "${GELF_OUTPUT_PORT}" ] ; then
  echo "WARNING no environmnet variable GELF_OUTPUT_PORT is define. Use \"${DEFAULT_GELF_OUTPUT_PORT}\" by default."
  export GELF_OUTPUT_PORT="${DEFAULT_GELF_OUTPUT_PORT}"
fi

if [ -z "${GELF_OUTPUT_PROTOCOL}" ] ; then
  echo "WARNING no environmnet variable GELF_OUTPUT_PROTOCOL is define. Use \"${DEFAULT_GELF_OUTPUT_PROTOCOL}\" by default."
  export GELF_OUTPUT_PROTOCOL="${DEFAULT_GELF_OUTPUT_PROTOCOL}"
fi

if [ -z "${GELF_OUTPUT_TLS}" ] ; then
  echo "WARNING no environmnet variable GELF_OUTPUT_TLS is define. Use \"${DEFAULT_GELF_OUTPUT_TLS}\" by default."
  export GELF_OUTPUT_TLS="${DEFAULT_GELF_OUTPUT_TLS}"
fi

if [ "${GELF_OUTPUT_PROTOCOL}" == "udp" -a "${GELF_OUTPUT_TLS}" != "false" ] ; then
  echo "ERROR UDP protocol does not support TLS encryption method."
  exit 1
fi

if [ -z "${GELF_STATIC_FIELDS}" ] ; then
  echo "WARNING no environmnet variable GELF_STATIC_FIELDS is define!"
fi

if [ -n "${TIMEZONE}" ] ; then
  echo ${TIMEZONE} >/etc/timezone && dpkg-reconfigure --frontend noninteractive tzdata
fi

OLDIFS=$IFS
IFS=","
GELF_STATIC_FIELDS_ARRAY=($GELF_STATIC_FIELDS)
IFS=$OLDIFS
for (( i=0; i<${#GELF_STATIC_FIELDS_ARRAY[@]}; i++ ))
do
  GELF_STATIC_FIELDS_CONTEXT=$( echo ${GELF_STATIC_FIELDS_ARRAY[$i]}| cut -d ':' -f 1)
  GELF_STATIC_FIELDS_VALUE=$( echo ${GELF_STATIC_FIELDS_ARRAY[$i]}| cut -d ':' -f 2-)
  field+=("      add_field => [ \"${GELF_STATIC_FIELDS_CONTEXT}\", \"${GELF_STATIC_FIELDS_VALUE}\" ]\\n")
done

output+=("  gelf {\\n")
output+=("    host => \"${GELF_OUTPUT_HOST}\"\\n")
output+=("    port => \"${GELF_OUTPUT_PORT}\"\\n")
output+=("    protocol => \"${GELF_OUTPUT_PROTOCOL}\"\\n")
output+=("    tls => \"${GELF_OUTPUT_TLS}\"\\n")
output+=("  }\\n")
if [ "x$DEBUG" == "x1" ] ; then
  output+=("  stdout {\n")
  output+=("    codec => rubydebug\\n")
  output+=("  }\\n")
fi

line_field=$(grep -n '#begin of mutate generate configutation' ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}|awk -F ':' '{print $1}')
sed -i "/#begin of mutate generate configutation/,/#end of mutate generate configutation/d" ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
head -n $(($line_field-1)) ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} > ${LOGSTASH_CONFIGURATION_FILE_TMP}
echo "    #begin of mutate generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
echo -e -n "${field[@]}" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
echo "    #end of mutate generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
tail -n +$line_field ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
cp ${LOGSTASH_CONFIGURATION_FILE_TMP} ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
line_output=$(grep -n '#begin of output gelf generate configuration' ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}|awk -F ':' '{print $1}')
sed -i "/#begin of output gelf generate configuration/,/#end of output gelf generate configuration/d" ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
head -n $(($line_output-1)) ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} > ${LOGSTASH_CONFIGURATION_FILE_TMP}
echo "  #begin of output gelf generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
echo -e -n "${output[@]}" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
echo "  #end of output gelf generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
tail -n +$line_output ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
cp ${LOGSTASH_CONFIGURATION_FILE_TMP} ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}


if [ "x${KEEP_CONFIG}" == "xtrue" ] ; then
  if [ "$(find /etc/logstash/conf.d -maxdepth 1 -type f|wc -l)" == "0" ] ; then
    if [ -f ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} ] ; then
      cp ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} ${LOGSTASH_CONFIGURATION_FILE}
    fi
  fi
else
  cp ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} ${LOGSTASH_CONFIGURATION_FILE}
fi

# Generate SSL cert/key for logstash-forwarder
FORWARDER_DIR="/opt/logstash-forwarder"
FORWARDER_KEY="logstash-forwarder.key"
FORWARDER_CRT="logstash-forwarder.crt"
DEFAULT_KEY="logstash.key"
DEFAULT_CRT="logstash.crt"
[ -z ${PUBLIC_HOSTNAME} ] && PUBLIC_HOSTNAME="$(hostname --fqdn)"
if [ ! -f "$FORWARDER_DIR/$FORWARDER_KEY" ]; then
  if [ -s "$FORWARDER_DIR/$DEFAULT_KEY" -a -s "$FORWARDER_DIR/$DEFAULT_KEY" ] ; then
    cp $FORWARDER_DIR/$DEFAULT_KEY $FORWARDER_DIR/$FORWARDER_KEY
    cp $FORWARDER_DIR/$DEFAULT_CRT $FORWARDER_DIR/$FORWARDER_CRT
  else
    echo "Generating new logstash-forwarder key"
    mkdir -p "${FORWARDER_DIR}"
    openssl req -x509 -batch -nodes -newkey rsa:4096 \
        -keyout "$FORWARDER_DIR/$FORWARDER_KEY" \
        -out "$FORWARDER_DIR/$FORWARDER_CRT" \
        -subj "/CN=${PUBLIC_HOSTNAME}" >/dev/null 2>/dev/null
  fi
else
  if [ -s "$FORWARDER_DIR/$DEFAULT_KEY" -a -s "$FORWARDER_DIR/$DEFAULT_KEY" ] ; then
    cp -f $FORWARDER_DIR/$DEFAULT_KEY $FORWARDER_DIR/$FORWARDER_KEY
    cp -f $FORWARDER_DIR/$DEFAULT_CRT $FORWARDER_DIR/$FORWARDER_CRT
  fi
fi

/etc/init.d/rsyslog stop >/dev/null 2>/dev/null

if [ "x$DEBUG" = "x1" -o "x$DEBUG" = "xtrue" ] ; then
  /opt/logstash/bin/logstash agent -f /etc/logstash/conf.d --debug
else
  /opt/logstash/bin/logstash agent -f /etc/logstash/conf.d 
fi
