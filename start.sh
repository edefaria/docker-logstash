#!/bin/bash

DEFAULT_GELF_OUTPUT_HOST="localhost"
DEFAULT_GELF_OUTPUT_PORT="12202"
DEFAULT_GELF_OUTPUT_PROTOCOL="tcp"
DEFAULT_GELF_OUTPUT_TLS="true"
DEFAULT_GELF_OUTPUT_CHECK_SSL="true"
DEFAULT_GELF_OUTPUT_TLS_VERSION="TLSv1_2"
DEFAULT_OUTPUT_PLUGIN="gelf"
DEFAULT_KAFKA_BROKER_HOST="localhost"
DEFAULT_KAFKA_BROKER_PORT="9092"
DEFAULT_KAFKA_TOPIC_ID="graylog"

LOGSTASH_CONFIGURATION_FOLDER="/etc/logstash/conf.d"
LOGSTASH_CONFIGURATION_FILE="/etc/logstash/conf.d/logstash.conf"
LOGSTASH_CONFIGURATION_FILE_TEMPLATE="/opt/logstash.conf"
LOGSTASH_CONFIGURATION_FOLDER_TEMPLATE="/opt/conf.d"
LOGSTASH_CONFIGURATION_FILE_TMP="/tmp/logstash.conf"

LOGSTASH_ROOT="/opt/logstash"
LOGSTASH_USER="logstash"
LOGSTASH_GROUP="logstash"
LOGSTASH_HOME="/var/lib/logstash"
LOGSTASH_HEAP_SIZE="500m"
LOGSTASH_LOG_FOLDER="/var/log/logstash"
LOGSTASH_LOG_FILE="${LOGSTASH_LOG_FOLDER}/logstash.log"
LOGSTASH_NICE="9"
LOGSTASH_START_OPTIONS=""

download_config() {
    local config_url="$1"
    local config_dir="$2"
    cd "${config_dir}" \
        && curl -Os "${config_url}" \
        || { echo "failed to download config $config_url" ; exit 1 ; }
}

download_tar() {
    local config_url="$1"
    local config_dir="$2"
    pushd "${config_dir}" > /dev/null
    curl -SL "${config_url}" \
        | tar -xC "${config_dir}" --strip-components=1 \
        || { echo "failed to download tar $config_url" ; exit 1 ; }
    popd > /dev/null
}

download_git() {
    local config_url="$1"
    local config_dir="$2"
    pushd "$(dirname ${config_dir})" > /dev/null
    git clone "${config_url}" "$(basename ${config_dir})" \
        || { echo "failed to git clone $config_url" ; exit 1 ; }
    popd > /dev/null
}

main_config() {
  if [ -n "${LOGSTASH_CONFIG_URL}" ] ; then
    case "${LOGSTASH_CONFIG_URL}" in
      *.conf)
        download_config "${LOGSTASH_CONFIG_URL}" "${LOGSTASH_CONFIGURATION_FOLDER}"
        ;;
      *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tar.xz)
        download_tar "${LOGSTASH_CONFIG_URL}" "${LOGSTASH_CONFIGURATION_FOLDER}"
       ;;
      *.git)
        download_git "${LOGSTASH_CONFIG_URL}" "${LOGSTASH_CONFIGURATION_FOLDER}"
        ;;
      *)
        echo "ERROR no extension file supported for: ${LOGSTASH_CONFIG_URL}"
        exit 1
        ;;
    esac
  else
    logstash_config
  fi
}

logstash_config() {
  if [ -z "${OUTPUT_PLUGIN}" ] ; then
     echo "WARNING no environmnet variable OUTPUT_PLUGIN is define. Use\"${DEFAULT_OUTPUT_PLUGIN}\" by default."
     export OUTPUT_PLUGIN="${DEFAULT_OUTPUT_PLUGIN}"
  fi

  if [ "${OUTPUT_PLUGIN}" == "kafka" ] ; then
    if [ -z "${KAFKA_BROKER_HOST}" ] ; then
      echo "WARNING no environmnet variable KAFKA_BROKER_HOST is define. Use \"${DEFAULT_KAFKA_BROKER_HOST}\" by default."
      export KAFKA_BROKER_HOST="${DEFAULT_KAFKA_BROKER_HOST}"
    fi
    if [ -z "${KAFKA_BROKER_PORT}" ] ; then
      echo "WARNING no environmnet variable KAFKA_BROKER_PORT is define. Use \"${DEFAULT_KAFKA_BROKER_PORT}\" by default."
      export KAFKA_BROKER_PORT="${DEFAULT_KAFKA_BROKER_PORT}"
    fi
    if [ -z "${KAFKA_TOPIC_ID}" ] ; then
      echo "WARNING no environmnet variable KAFKA_TOPIC_ID is define. Use \"${DEFAULT_KAFKA_TOPIC_ID}\" by default."
      export KAFKA_TOPIC_ID="${DEFAULT_KAFKA_TOPIC_ID}"
    fi
  elif [ "${OUTPUT_PLUGIN}" == "none" ] ; then
    echo "WARNING no OUTPUT_PLUGIN selected."
  else
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
    if [ -z "${GELF_OUTPUT_CHECK_SSL}" ] ; then
      echo "WARNING no environmnet variable GELF_OUTPUT_CHECK_SSL is define. Use \"${DEFAULT_GELF_OUTPUT_CHECK_SSL}\" by default."
      export GELF_OUTPUT_CHECK_SSL=${DEFAULT_GELF_OUTPUT_CHECK_SSL}
    fi
    if [ -z "${GELF_OUTPUT_TLS_VERSION}" ] ; then
      echo "WARNING no environmnet variable GELF_OUTPUT_TLS_VERSION is define. Use \"${DEFAULT_GELF_OUTPUT_TLS_VERSION}\" by default."
      export GELF_OUTPUT_TLS_VERSION=${DEFAULT_GELF_OUTPUT_TLS_VERSION}
    fi
  fi

  if [ -z "${GELF_STATIC_FIELDS}" ] ; then
    echo "WARNING no environmnet variable GELF_STATIC_FIELDS is define!"
    if [ ! -f ${LOGSTASH_CONFIGURATION_FILE} ] ; then
      echo "ERROR no previous configuration file found, exiting!"
      echo "Please set GELF_STATIC_FIELDS environmnet variable to your container, to generate a configuration file."
      exit 1
    fi
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

  if [ "${OUTPUT_PLUGIN}" == "kafka" ] ; then
    output+=("  kafka {\\n")
  #  output+=("    codec => gelf { custom_fields => [ 'testing', 'logstash' ] }\\n")
    output+=("    codec => gelf {}\\n")
    output+=("    broker_list => \"${KAFKA_BROKER_HOST}:${KAFKA_BROKER_PORT}\"\\n")
    output+=("    topic_id => \"${KAFKA_TOPIC_ID}\"\\n")
    output+=("  }\\n")
  elif [ "${OUTPUT_PLUGIN}" == "none" ] ; then
    touch /tmp/none
  else
    output+=("  gelf {\\n")
    output+=("    host => \"${GELF_OUTPUT_HOST}\"\\n")
    output+=("    port => \"${GELF_OUTPUT_PORT}\"\\n")
    output+=("    protocol => \"${GELF_OUTPUT_PROTOCOL}\"\\n")
    output+=("    tls => \"${GELF_OUTPUT_TLS}\"\\n")
    output+=("    check_ssl => \"${GELF_OUTPUT_CHECK_SSL}\"\\n")
    output+=("    tls_version => \"${GELF_OUTPUT_TLS_VERSION}\"\\n")
    output+=("  }\\n")
  fi
  if [ "x$DEBUG" == "x1" ] ; then
    output_stdout+=("  stdout {\\n")
    output_stdout+=("    codec => rubydebug\\n")
    output_stdout+=("  }\\n")
  elif [ "x$STDOUT" == "x1" -o  "x$STDOUT" == "xtrue" ] ; then
    output_stdout+=("  stdout {}\n")
  fi

  if [ -n "${field}" ] ; then
    line_field=$(grep -n '#begin of mutate generate configutation' ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}|awk -F ':' '{print $1}')
    sed -i "/#begin of mutate generate configutation/,/#end of mutate generate configutation/d" ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
    head -n $(($line_field-1)) ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} > ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo "    #begin of mutate generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo -e -n "${field[@]}" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo "    #end of mutate generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    tail -n +$line_field ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    cp ${LOGSTASH_CONFIGURATION_FILE_TMP} ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
  fi
  if [ -n "${output}" ] ; then
    line_output=$(grep -n '#begin of output gelf generate configuration' ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}|awk -F ':' '{print $1}')
    sed -i "/#begin of output gelf generate configuration/,/#end of output gelf generate configuration/d" ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
    head -n $(($line_output-1)) ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} > ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo "  #begin of output gelf generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo -e -n "${output[@]}" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo "  #end of output gelf generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    tail -n +$line_output ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    cp ${LOGSTASH_CONFIGURATION_FILE_TMP} ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
  fi
  if [ -n "${output_stdout}" ] ; then
    line_output_stdout=$(grep -n '#begin of output stdout generate configuration' ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}|awk -F ':' '{print $1}')
    sed -i "/#begin of output stdout generate configuration/,/#end of output stdout generate configuration/d" ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
    head -n $(($line_output_stdout-1)) ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} > ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo "  #begin of output stdout generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo -e -n "${output_stdout[@]}" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    echo "  #end of output stdout generate configutation" >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    tail -n +$line_output_stdout ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} >> ${LOGSTASH_CONFIGURATION_FILE_TMP}
    cp ${LOGSTASH_CONFIGURATION_FILE_TMP} ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE}
  fi

  if [ "x${KEEP_CONFIG}" == "xtrue" ] ; then
    if [ "$(find /etc/logstash/conf.d -maxdepth 1 -type f|wc -l)" == "0" ] ; then
      if [ -f ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} ] ; then
        cp ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} ${LOGSTASH_CONFIGURATION_FILE}
      fi
    fi
  else
    cp ${LOGSTASH_CONFIGURATION_FILE_TEMPLATE} ${LOGSTASH_CONFIGURATION_FILE}
    if [ -d ${LOGSTASH_CONFIGURATION_FOLDER_TEMPLATE} ] ; then
      cp -ar ${LOGSTASH_CONFIGURATION_FOLDER_TEMPLATE}/* ${LOGSTASH_CONFIGURATION_FOLDER}
    fi
  fi
}

logstash_forwarder_keygen() {
  #Generate SSL cert/key for logstash-forwarder
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
}

kill_logstash () {
  kill $(ps ux | grep logstash | grep java | grep agent | awk '{ print $2}')
  exit
}

check_logstash () {
  # create logstash group
  if ! getent group ${LOGSTASH_GROUP} >/dev/null; then
    groupadd -r ${LOGSTASH_GROUP}
  fi
  # create logstash user
  if ! getent passwd ${LOGSTASH_USER} >/dev/null; then
    useradd -M -r -g ${LOGSTASH_GROUP} -d ${LOGSTASH_HOME} \
      -s /usr/sbin/nologin -c "LogStash Service User" ${LOGSTASH_USER}
  fi
  # chown folder
  chown -R ${LOGSTASH_USER}:${LOGSTASH_GROUP} ${LOGSTASH_ROOT}
  [ ! -d "${LOGSTASH_LOG_FOLDER}" ] && mkdir ${LOGSTASH_LOG_FOLDER}
  chown ${LOGSTASH_USER}:${LOGSTASH_GROUP} ${LOGSTASH_LOG_FOLDER}
  [ ! -d "${LOGSTASH_HOME}" ] && mkdir -p ${LOGSTASH_HOME}
  chown ${LOGSTASH_USER}:${LOGSTASH_GROUP} ${LOGSTASH_HOME}
}


start_logstash () {
  if [ `id -u` -ne 0 ]; then
   echo "You need root privileges to run this script"
   exit 1
  fi
  LOGSTASH_JAVA_OPTIONS="${LOGSTASH_JAVA_OPTIONS} -Djava.io.tmpdir=${LOGSTASH_HOME}"
  HOME=${LOGSTASH_HOME}
  export PATH HOME LOGSTASH_HEAP_SIZE LOGSTASH_JAVA_OPTS LOGSTASH_USE_GC_LOGGING
  program="${LOGSTASH_ROOT}/bin/logstash"
  args="agent -f ${LOGSTASH_CONFIGURATION_FOLDER} "
  if [ "x$LOG" = "x1" -o "x$LOG" = "xtrue" ] ; then
    args+="-l ${LOGSTASH_LOG_FILE} "
  fi
  if [ "x$DEBUG" = "x1" -o "x$DEBUG" = "xtrue" ] ; then
    args+="--debug "
  fi
  args+="${LOGSTASH_START_OPTIONS}"
  if [ "x$CHROOT" = "x1" -o "x$CHROOT" = "xtrue" ] ; then
    # Run the program!
    nice -n ${LOGSTASH_NICE} chroot --userspec $LOGSTASH_USER:$LOGSTASH_GROUP / sh -c "
      cd $LOGSTASH_HOME
      exec $program $args" &
  else
    $program $args &
  fi
}


main_config

logstash_forwarder_keygen

[ -x "/etc/init.d/rsyslog" ] && /etc/init.d/rsyslog stop >/dev/null 2>/dev/null

trap kill_logstash SIGINT SIGTERM SIGHUP

check_logstash
start_logstash
pid=$!
wait $pid
