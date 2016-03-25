# Vault Cubbyhole Authentication Model example

Based on this article by Hashicorp: https://www.hashicorp.com/blog/vault-cubbyhole-principles.html

## Run the example

Start Vault:

```sh
vault server -dev
```

Add the secret password:

```sh
vault write secret/my-service-db-password password=s3cr3t
```

Install gems:
```sh
bundle install
```

Run script:
```sh
ruby securely_launch.rb
```
