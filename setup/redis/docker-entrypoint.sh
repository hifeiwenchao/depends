#!/bin/sh
set -eu

: "${REDIS_USERNAME:?REDIS_USERNAME is required}"
: "${REDIS_PASSWORD:?REDIS_PASSWORD is required}"

# ACL files use whitespace-delimited tokens and operator prefixes. Restrict both
# values to RFC 3986 unreserved characters so direct ACL syntax is unambiguous.
case "$REDIS_USERNAME" in
  *[!A-Za-z0-9._~-]*)
    echo "REDIS_USERNAME must contain only URL-safe characters: A-Z a-z 0-9 . _ ~ -" >&2
    exit 64
    ;;
esac
case "$REDIS_PASSWORD" in
  *[!A-Za-z0-9._~-]*)
    echo "REDIS_PASSWORD must contain only URL-safe characters: A-Z a-z 0-9 . _ ~ -" >&2
    exit 64
    ;;
esac

mkdir -p /run/redis
umask 077
if [ "$REDIS_USERNAME" = default ]; then
  printf 'user default reset on >%s ~* &* +@all\n' "$REDIS_PASSWORD" > /run/redis/users.acl
else
  {
    printf 'user default reset off\n'
    printf 'user %s reset on >%s ~* &* +@all\n' "$REDIS_USERNAME" "$REDIS_PASSWORD"
  } > /run/redis/users.acl
fi

# The official image starts as root so its entrypoint can repair /data ownership,
# then drops to the redis user. Keep the tmpfs ACL traversable/readable after that drop.
chown redis:redis /run/redis /run/redis/users.acl
chmod 700 /run/redis
chmod 600 /run/redis/users.acl

exec /usr/local/bin/docker-entrypoint.sh "$@"
