# ACA Web App with Redis

```
brew install redis
cd infra
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

on `web` container app, run:

```
apt update
apt install -y redis-tools
redis-cli -h redis PING
```