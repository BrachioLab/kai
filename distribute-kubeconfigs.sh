#!/bin/bash
# distribute-kubeconfigs.sh USER [USER ...] — copy each user's kai kubeconfig
# into their home directory (keeping the username in the filename). Run as ROOT
# on the control node, where the generated kai-kubeconfig-<user>.yaml files live.
#
# Usage:
#   sudo ./distribute-kubeconfigs.sh alokshah
#   sudo ./distribute-kubeconfigs.sh alice bob carol
#
# Overridable via env (defaults suit the locust cluster):
#   KAI_KUBECONFIG_DIR  dir holding kai-kubeconfig-<user>.yaml  (default: /home/exwong/locust-kubeconfigs)
#   KAI_ADMIN_USER      owner of those source files             (default: exwong)
#
# NFS root_squash workaround: /home is NFS, so root can neither read the admin's
# 0600 source files nor write into user homes. We read the source AS the admin
# and write each home AS that user (sudo -u); the only chown happens on local
# /tmp, where root isn't squashed. The stage dir is 1777 so the admin can stage
# and each target user can read its own file back. Files stay 0600/owned by the
# target user, so no one can read another user's token.
set -u

SRC="${KAI_KUBECONFIG_DIR:-/home/exwong/locust-kubeconfigs}"
ADMIN="${KAI_ADMIN_USER:-exwong}"

if [ "$#" -eq 0 ]; then
  echo "usage: sudo $0 USER [USER ...]" >&2
  exit 2
fi

STAGE=$(mktemp -d /tmp/kc-stage.XXXXXX); chmod 1777 "$STAGE"
for u in "$@"; do
  src="$SRC/kai-kubeconfig-$u.yaml"
  sudo -u "$ADMIN" test -r "$src"             || { echo "SKIP $u: source missing ($src)"; continue; }
  sudo -u "$ADMIN" cp "$src" "$STAGE/$u.yaml" || { echo "SKIP $u: stage failed";  continue; }
  chown "$u:$u" "$STAGE/$u.yaml"; chmod 600 "$STAGE/$u.yaml"
  sudo -u "$u" test -d "/home/$u"             || { echo "SKIP $u: /home/$u missing"; continue; }
  if sudo -u "$u" cp "$STAGE/$u.yaml" "/home/$u/kai-kubeconfig-$u.yaml" \
     && sudo -u "$u" chmod 600 "/home/$u/kai-kubeconfig-$u.yaml"; then
       echo "OK   $u -> /home/$u/kai-kubeconfig-$u.yaml"
  else echo "FAIL $u: write to home"; fi
done
rm -rf "$STAGE"
echo "Done. Tell each user: kai setup ~/kai-kubeconfig-<username>.yaml"
