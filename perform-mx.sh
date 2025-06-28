#!/bin/bash
set -euo pipefail

log() {
  echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "🔍 Detecting OS..."
OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
VERSION_ID=$(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release | tr -d '"')
MAJOR_VERSION=${VERSION_ID%%.*}

log "➡️ OS Detected: $OS $VERSION_ID"

log "🔧 Cleaning up EPEL tbi repo..."
rm -f /etc/yum.repos.d/home*tbi* || true

log "🔑 Importing MySQL GPG key..."
rpm --import https://repo.mysql.com/RPM-GPG-KEY-mysql-2023

log "🔍 Checking Grafana GPG key..."
if grep -q "^gpgkey = https://rpm.grafana.com/gpg.key" /etc/yum.repos.d/grafana.repo; then
  log "✅ Grafana key already correct."
else
  sed -i 's|^gpgkey =.*|gpgkey = https://rpm.grafana.com/gpg.key|' /etc/yum.repos.d/grafana.repo || true
  log "🛠 Updated Grafana GPG key."
fi

log "🔄 Rebuilding RPM database..."
rpm --rebuilddb

if [[ "$OS" == "Amazon Linux" && "$VERSION_ID" == "2023" ]]; then
  log "📦 Updating Amazon Linux 2023..."

  yum --setopt=cachedir=/tmp/yum-cache update -y --releasever=latest --skip-broken

  if grep -q '#!/usr/bin/python3$' /usr/bin/yum; then
    log "ℹ️ Skipping yum shebang fix — Python handling removed."
  fi

elif [[ "$OS" == "Red Hat Enterprise Linux" && "$MAJOR_VERSION" == "8" ]]; then
  log "📦 Updating RHEL 8..."

  if yum repolist | grep -q 'rhel-8-for-x86_64-baseos-eus-rhui-rpms'; then
    log "🛠 Switching from EUS to non-EUS repos..."
    yum -y --disablerepo='*' remove 'rhui-azure-rhel8-eus' || true
    wget -q -O /tmp/rhui.conf https://rhelimage.blob.core.windows.net/repositories/rhui-microsoft-azure-rhel8.config
    yum -y --config=/tmp/rhui.conf install rhui-azure-rhel8
    echo 8.10 > /etc/dnf/vars/releasever
  fi

  yum --setopt=cachedir=/tmp/yum-cache update -y --releasever=8.10 --skip-broken

else
  log "📦 Performing generic yum update..."

  yum --setopt=cachedir=/tmp/yum-cache update -y --skip-broken
fi

log "🧹 Cleaning yum cache..."
yum clean all

log "🧼 Cleaning Tomcat cache..."
service mstr tomcatstop || true
rm -rf /opt/apache/tomcat/latest/work/Catalina/localhost/* || true

log "✅ Script complete. No reboot performed. No Python changes applied."
