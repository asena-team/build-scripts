#!/usr/bin/env bash

set -eo pipefail

cd "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exit_err() {
  echo >&2 "${1}"
  exit 1
}

usage() {
  echo "Usage: $0 [--remote-addr <IPv4 | localhost>] [--domain <string>] [--docker <boolean>]" 1>&2
  exit 0
}

valid_ip() {
  local ip=$1
  local stat=1

  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    OIFS=$IFS
    IFS='.'
    ip=($ip)
    IFS=$OIFS
    [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]

    stat=$?
  elif [[ "$ip" == "localhost" ]]; then
    stat=0
  fi

  return $stat
}

# flags
# - remote-addr=string (IPv4 | localhost)
# - domain=string
# - docker=boolean
opts() {
  while test $# -gt 0; do
    case "$1" in
    --remote-addr)
      shift
      if ! valid_ip "$1"; then
        exit_err "\"$1\" is an invalid IPv4 address. Please enter a valid IPv4 address."
      fi

      IP="$1"
      shift
      ;;
    --domain)
      shift
      DOMAIN="$1"
      shift
      ;;
    --docker)
      shift
      if [[ "$1" != "true" && "$1" != "false" ]]; then usage; fi

      DOCKER="$1"
      shift
      ;;
    *)
      break
      ;;
    esac
  done

  if [ -z ${DOMAIN+x} ] || [ -z ${IP+x} ]; then
    usage
  fi

  if [ -z ${DOCKER+x} ]; then DOCKER="false"; fi
}

detect_package_manager_and_install_nginx() {
  if [[ -f /usr/bin/apt ]]; then
    PACKAGE_MANAGER=/usr/bin/apt
  elif [[ -n $(type apt) ]]; then
    PACKAGE_MANAGER=$(type -p apt)
  elif [[ -f /usr/bin/yum ]]; then
    PACKAGE_MANAGER=/usr/bin/yum
  elif [[ -n $(type yum) ]]; then
    PACKAGE_MANAGER=$(type -p yum)
  else
    exit_err "Your package manager not supported. Please use Docker install mode."
  fi

  $PACKAGE_MANAGER install nginx
}

# for only apt or yum manager
install_manuel() {
  detect_package_manager_and_install_nginx

  systemctl enable nginx
  systemctl restart nginx
}

install_docker() {
  if [[ -z $(type docker) ]]; then
    exit_err "Executable docker binary not found. Please install docker."
  fi

  if ! docker build . -t nginx-reverse-proxy; then
    exit_err "Docker image build error."
  fi

  docker run -d -p 80:80 --name nginx-reverse-proxy nginx-reverse-proxy
}

parse_conf() {
  conf=$(<proxy.conf)
  conf="${conf/\{domain\}/$DOMAIN}"
  conf="${conf/\{remote-addr\}/$IP}"

  local file
  if [[ $DOCKER == "true" ]]; then
    file=parsed-proxy.conf
  else
    file=/etc/nginx/conf.d/"$DOMAIN".conf
  fi

  echo "$conf">"$file"
}

main() {
  if [[ $EUID -ne 0 ]]; then
    exit_err "This script must be run as root."
  fi

  opts "$@"

  if [[ ! -f proxy.conf ]]; then
    exit_err "proxy.conf file not found. Please check your local files."
  fi

  parse_conf

  if [[ $DOCKER == "true" ]]; then
    install_docker
  else
    install_manuel
  fi
}

main "$@"
