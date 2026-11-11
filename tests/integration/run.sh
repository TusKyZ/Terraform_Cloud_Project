#!/usr/bin/env bash
# Local test of the compute module's user_data, with Docker and no AWS. See
# README.md in this folder for what it proves and what it does not.
#
# Usage, from the repository root: bash tests/integration/run.sh
# Needs bash, curl, a running Docker Engine 26 or newer (for volume-subpath
# mounts), and terraform on the PATH or TERRAFORM=<path to terraform>.
set -uo pipefail

# Git Bash on Windows turns arguments that start with / into Windows paths;
# Docker must get container paths unchanged.
export MSYS_NO_PATHCONV=1

tf="${TERRAFORM:-terraform}"
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"

# Windows programs need C:/... paths; elsewhere a path is used as it is.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

fails=0
# check <description> <actual> <expected>
check() {
  if [ "$2" = "$3" ]; then
    echo "PASS $1"
  else
    echo "FAIL $1: expected '$3', got '$2'"
    fails=$((fails + 1))
  fi
}

# Throwaway passwords, made fresh for each run.
random() { od -An -N12 -tx1 /dev/urandom | tr -d ' \n'; }

remove_docker_objects() {
  docker rm -f wpitest-db wpitest-writer wpitest-wp wpitest-wp-notls >/dev/null 2>&1
  docker volume rm wpitest-run wpitest-html wpitest-html-notls >/dev/null 2>&1
  docker network rm wpitest >/dev/null 2>&1
}
trap 'remove_docker_objects; rm -rf "$work"' EXIT
remove_docker_objects

image="$(sed -n 's/^wordpress_image *= *"\([^"]*\)".*/\1/p' "$repo/terraform.tfvars")"
key_names="AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT"

echo "Local Docker test of the compute module's user_data"
echo "Run on $(date -u '+%Y-%m-%d %H:%M UTC'), Docker Engine $(docker version --format '{{.Server.Version}}')"
for i in mysql:8.4 amazonlinux:2023 "$image"; do
  docker pull -q "$i" >/dev/null || { echo "FAIL cannot pull $i"; exit 1; }
  echo "Image: $(docker image inspect --format '{{index .RepoDigests 0}}' "$i")"
done
echo

# Render user_data with terraform console, from the module's template and
# fake values for its variables.
key_list="$(printf '"%s", ' $key_names)"
cat > "$work/expr.txt" <<EOF
templatefile("$(native "$repo")/modules/compute/templates/user_data.sh.tftpl", { region = "ap-southeast-3", db_secret_arn = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:rds!db-test-AbCdEf", keys_secret_arn = "arn:aws:secretsmanager:ap-southeast-3:111122223333:secret:web-school-prod-wordpress-keys-test", key_names = [${key_list%, }], db_address = "db.invalid", db_port = 3306, db_name = "wordpress", domain_name = "webschool.example", wordpress_image = "$image" })
EOF
(cd "$work" && "$tf" console -no-color < expr.txt > console.txt 2>&1)
if [ "$(head -1 "$work/console.txt")" != "<<EOT" ]; then
  echo "FAIL terraform console could not render user_data:"
  cat "$work/console.txt"
  exit 1
fi
sed '1d;$d' "$work/console.txt" > "$work/user_data.sh"
sed -n "/<<'SCRIPT'/,/^SCRIPT$/p" "$work/user_data.sh" | sed '1d;$d' > "$work/wordpress-secrets"
sed -n "/<<'ENV'/,/^ENV$/p" "$work/user_data.sh" | sed '1d;$d' |
  sed 's/^WORDPRESS_DB_HOST=.*/WORDPRESS_DB_HOST=wpitest-db:3306/' > "$work/wordpress.env"
sed "s/ define('MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL);//" "$work/wordpress.env" > "$work/wordpress-notls.env"
units="wordpress-secrets.service wordpress-secrets.timer wordpress.service"
for u in $units; do
  sed -n "/^cat > \/etc\/systemd\/system\/$u <<'UNIT'$/,/^UNIT$/p" "$work/user_data.sh" | sed '1d;$d' > "$work/$u"
done

echo "== user_data"
check "user_data is valid bash" "$(bash -n "$work/user_data.sh" 2>&1 && echo ok)" "ok"
check "the secrets script is valid bash" "$(bash -n "$work/wordpress-secrets" 2>&1 && echo ok)" "ok"
check "the control copy has no MYSQL_CLIENT_FLAGS" "$(grep -c MYSQL_CLIENT_FLAGS "$work/wordpress-notls.env")" "0"

db_password="$(random)"
root_password="$(random)"
write_db_secret() { printf '%s' "$1" > "$work/db.json"; docker cp "$(native "$work/db.json")" wpitest-writer:/fake/db.json >/dev/null; }
keys_json="{"
for n in $key_names; do keys_json="$keys_json\"$n\":\"test-$n\","; done
printf '%s' "${keys_json%,}}" > "$work/keys.json"

docker network create wpitest >/dev/null

echo "== MySQL 8.4, standing in for RDS"
docker run -d --name wpitest-db --network wpitest \
  -e MYSQL_ROOT_PASSWORD="$root_password" -e MYSQL_DATABASE=wordpress \
  -e MYSQL_USER=wpadmin -e MYSQL_PASSWORD="$db_password" \
  mysql:8.4 --require-secure-transport=ON >/dev/null
sql() { docker exec -e MYSQL_PWD="$root_password" wpitest-db mysql -uroot --protocol=tcp -h127.0.0.1 -N -e "$1" 2>/dev/null; }
for i in $(seq 1 60); do sql 'SELECT 1' >/dev/null && break; sleep 3; done
check "MySQL requires TLS for every connection" "$(sql 'SELECT @@require_secure_transport')" "1"

echo "== Amazon Linux 2023: packages, systemd units and the secrets script"
docker run -d --name wpitest-writer -v wpitest-run:/run amazonlinux:2023 sleep infinity >/dev/null
docker exec wpitest-writer dnf install -y -q jq docker systemd >/dev/null 2>&1
check "dnf installs jq and docker" "$(docker exec wpitest-writer rpm -q jq docker >/dev/null && echo ok)" "ok"
docker exec wpitest-writer mkdir -p /fake
docker cp "$(native "$here/fake-aws")" wpitest-writer:/usr/local/bin/aws >/dev/null
docker cp "$(native "$work/keys.json")" wpitest-writer:/fake/keys.json >/dev/null
docker cp "$(native "$work/wordpress-secrets")" wpitest-writer:/usr/local/sbin/wordpress-secrets >/dev/null
for u in $units; do docker cp "$(native "$work/$u")" "wpitest-writer:/etc/systemd/system/$u" >/dev/null; done
docker exec wpitest-writer sh -c 'chmod 0755 /usr/local/bin/aws; chmod 0700 /usr/local/sbin/wordpress-secrets; chmod 0644 /etc/systemd/system/wordpress*'
write_db_secret "{\"username\":\"wpadmin\",\"password\":\"$db_password\"}"
check "systemd accepts the three units" \
  "$(docker exec wpitest-writer sh -c 'cd /etc/systemd/system && systemd-analyze verify wordpress-secrets.service wordpress-secrets.timer wordpress.service' 2>&1 && echo ok)" "ok"
secrets() { docker exec wpitest-writer /usr/local/sbin/wordpress-secrets >/dev/null 2>&1 && echo ok || echo stopped; }
check "the secrets script runs as root" "$(secrets)" "ok"
check "it writes 10 files owned by uid 33 with mode 0400" \
  "$(docker exec wpitest-writer sh -c 'echo $(ls /run/wordpress | wc -l) $(stat -c %u:%g:%a /run/wordpress/* | sort -u)')" "10 33:33:400"

echo "== WordPress: $image"
secret_mount="type=volume,source=wpitest-run,target=/run/secrets/wordpress,volume-subpath=wordpress,readonly"
docker run -d --name wpitest-wp --network wpitest -p 127.0.0.1:18080:80 \
  --env-file "$(native "$work/wordpress.env")" --mount "$secret_mount" \
  --volume wpitest-html:/var/www/html "$image" >/dev/null
home() { curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H 'Host: origin.webschool.example' "http://127.0.0.1:$1/"; }
wait_for() { for i in $(seq 1 60); do case "$(home "$1")" in 000*) sleep 3 ;; *) return ;; esac; done; }
wait_for 18080
installer="302 https://webschool.example/wp-admin/install.php"
check "WordPress reaches MySQL over TLS: the home page redirects to the installer" "$(home 18080)" "$installer"
started="$(docker inspect --format '{{.State.StartedAt}}' wpitest-wp)"
check "WORDPRESS_CONFIG_EXTRA is valid PHP with the site address, TLS and no file changes" \
  "$(docker exec wpitest-wp php -r 'eval(getenv("WORDPRESS_CONFIG_EXTRA")); echo json_encode([WP_HOME, WP_SITEURL, MYSQL_CLIENT_FLAGS === MYSQLI_CLIENT_SSL, DISALLOW_FILE_MODS, AUTOMATIC_UPDATER_DISABLED], JSON_UNESCAPED_SLASHES);')" \
  '["https://webschool.example","https://webschool.example",true,true,true]'
check "the web server user reads a key from its file" \
  "$(docker exec -u www-data wpitest-wp php -r 'echo file_get_contents(getenv("WORDPRESS_AUTH_KEY_FILE"));')" "test-AUTH_KEY"
check "another user cannot read the secret files" \
  "$(docker exec -u 1000 wpitest-wp cat /run/secrets/wordpress/DB_PASSWORD 2>&1 | grep -c 'Permission denied')" "1"
check "the secrets folder is read-only in the container" \
  "$(docker exec wpitest-wp touch /run/secrets/wordpress/x 2>&1 | grep -c 'Read-only file system')" "1"
env_json="$(docker inspect --format '{{json .Config.Env}}' wpitest-wp)"
check "the container's environment has 10 _FILE settings and no secret value" \
  "$(grep -o '_FILE=' <<<"$env_json" | wc -l | tr -d ' ') $(grep -o -e "$db_password" -e 'test-AUTH' <<<"$env_json" | wc -l | tr -d ' ')" "10 0"

echo "== Control: the same WordPress without MYSQL_CLIENT_FLAGS"
docker run -d --name wpitest-wp-notls --network wpitest -p 127.0.0.1:18081:80 \
  --env-file "$(native "$work/wordpress-notls.env")" --mount "$secret_mount" \
  --volume wpitest-html-notls:/var/www/html "$image" >/dev/null
wait_for 18081
check "MySQL refuses WordPress without TLS (HTTP 500)" "$(home 18081)" "500 "

echo "== Password rotation without a restart"
new_password="$(random)"
sql "ALTER USER 'wpadmin'@'%' IDENTIFIED BY '$new_password'"
check "with the old password file, WordPress fails" "$(home 18080)" "500 "
write_db_secret "{\"username\":\"wpadmin\",\"password\":\"$new_password\"}"
check "the secrets script writes the new password" "$(secrets)" "ok"
check "WordPress works again" "$(home 18080)" "$installer"
check "the container was not restarted" \
  "$(docker inspect --format '{{.RestartCount}} {{.State.StartedAt}}' wpitest-wp)" "0 $started"

echo "== A bad fetch keeps the old files"
files="$(docker exec wpitest-writer sh -c 'sha256sum /run/wordpress/*')"
bad_fetch() {  # bad_fetch <description>
  check "$1: the script stops" "$(secrets)" "stopped"
  check "$1: every old file stays" "$(docker exec wpitest-writer sh -c 'sha256sum /run/wordpress/*')" "$files"
  check "$1: no staging folder is left" "$(docker exec wpitest-writer sh -c 'ls -d /run/wordpress-new.* 2>/dev/null | wc -l')" "0"
}
for mode in fail empty null none; do
  docker exec wpitest-writer sh -c "echo $mode > /fake/mode"
  case "$mode" in
    fail) bad_fetch "the AWS CLI fails" ;;
    empty) bad_fetch "the AWS CLI prints nothing" ;;
    null) bad_fetch "the AWS CLI prints null" ;;
    none) bad_fetch "the AWS CLI prints None" ;;
  esac
done
docker exec wpitest-writer rm -f /fake/mode
write_db_secret '{"username":"wpadmin","password":null}'
bad_fetch "the password is null"
write_db_secret '{"username":"wpadmin","password":""}'
bad_fetch "the password is empty"
write_db_secret '{"username":"wpadmin"}'
bad_fetch "the password is missing"
check "WordPress still works after the bad fetches" "$(home 18080)" "$installer"
write_db_secret "{\"username\":\"wpadmin\",\"password\":\"$new_password\"}"
check "a good fetch works again" "$(secrets)" "ok"

echo
echo "RESULT: $fails failure(s)"
[ "$fails" -eq 0 ]
