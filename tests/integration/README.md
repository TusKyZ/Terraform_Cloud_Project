# Local Docker test of user_data

`run.sh` checks the compute module's user_data with Docker on one machine, without AWS. It renders `modules/compute/templates/user_data.sh.tftpl` with `terraform console`, then runs its pieces:

- MySQL 8.4 with `require_secure_transport=ON`, standing in for RDS.
- An Amazon Linux 2023 container that installs the same packages as user_data, checks the three systemd units with `systemd-analyze verify`, and runs the real secrets script as root. A fake AWS CLI (`fake-aws`) prints test secrets in place of Secrets Manager.
- The WordPress image from `terraform.tfvars`, with the rendered env file and the secrets folder mounted read-only, as on an instance.

The plan-time tests in `tests/*.tftest.hcl` check the Terraform configuration; this test checks that the script and the container settings it writes work.

## What it proves

- The rendered user_data and the secrets script are valid bash, systemd accepts the three units, and `dnf` installs `docker` and `jq` on Amazon Linux 2023.
- The secrets script writes the 10 files (the database user and password, and the eight WordPress keys) owned by uid 33, the web server user in the image, with mode 0400.
- WordPress reads the database credentials and the keys from those files and reaches MySQL over TLS: the home page redirects to the installer. The same container without `MYSQL_CLIENT_FLAGS` gets HTTP 500, because MySQL refuses connections without TLS.
- `WORDPRESS_CONFIG_EXTRA` is valid PHP and sets the site address, TLS to the database, `DISALLOW_FILE_MODS` and `AUTOMATIC_UPDATER_DISABLED`.
- No secret value is in the container's environment, other users cannot read the files, and the container cannot write to the folder.
- Password rotation: after the database password changes, WordPress fails until the script rewrites the file, then works again without a container restart, because the container mounts the folder, not single files.
- A bad fetch keeps every old file and leaves no staging folder: the AWS CLI failing, printing nothing, printing `null` or `None`, and a null, empty or missing password.

## What it does not prove

- Anything on AWS. The AWS CLI is a fake, so IAM permissions, Secrets Manager, KMS, the instance metadata and its hop limit, the VPC, security groups, network ACLs, the ALB, CloudFront and the Auto Scaling group are not exercised.
- RDS itself. MySQL runs locally with its own certificate, so the RDS parameter group, the managed rotation and the RDS certificate are not tested.
- systemd at run time. The units are checked, not started, so the one-minute timer, the boot order and `Restart=always` are not exercised. user_data runs in pieces, not through cloud-init, and the secrets folder is a Docker volume, not the instance's in-memory `/run`.
- The module's own inputs. The render uses fake values for the template's variables; the plan-time tests check what the module passes to the template.
- A working site. WordPress is only taken as far as its installer.

## Run it

From the repository root, with Docker running:

```bash
bash tests/integration/run.sh
```

- On Windows, use Git Bash. If `terraform` is not on the PATH, set `TERRAFORM` to its full path.
- It needs Docker Engine 26 or newer, for the `volume-subpath` mount, and `curl`.
- It pulls `mysql:8.4`, `amazonlinux:2023` and the WordPress image, and takes a few minutes.
- It uses ports 18080 and 18081 on 127.0.0.1 and Docker objects named `wpitest-*`, which it removes at the end. The pulled images stay.
- Passwords are random for each run, so none is stored in the repository.
- It prints one PASS or FAIL line per check and exits non-zero if any check fails. `docs/evidence/integration-test.txt` holds the output of a run.
