require 'vault'
require 'colorize'

# assume an app needs a secret password, and it has been written by a
# priveleged/trusted user or process into path secret/my-service-db-password.
# to test this script, run this before:
# vault write secret/my-service-db-password password=s3cr3t

# this script represents a deployment mechanism (like jenkins) that can
# securely store a token for use with vault to create deployment specific
# tokens.

puts '-- deployment process creating temp and permanent tokens'.green

# priveleged process (jenkins, etc) that runs this can obtain this token
# securely
token = 'a4f5dc49-d93e-d0d8-0bfd-e405a3e05c4e'
vault_address = 'http://127.0.0.1:8200'

deployer_client = Vault::Client.new(address: vault_address, token: token)

# launcher/deployer process uses secure token to create 2 new tokens:
# temp token can only be used 2 times, and has a short ttl.
temp = deployer_client.auth_token.create({ :ttl => '15s', :num_uses => 2 })[:auth][:client_token]
# permanent token can be used any number of times w/ no ttl.
perm = deployer_client.auth_token.create({})[:auth][:client_token]

puts "temporary token is #{temp}"
puts "permanent token is #{perm}"

# using the first use of token #1, store the permanent token in cubbyhole
temp_client = Vault::Client.new(address: vault_address, token: temp)
temp_client.logical.write("cubbyhole/app-token", { :token => perm })

# example ecs/marathon/whatever deploy - pseudocode
# SomeContainerScheduler.deploy({
#   :id => 'my-service',
#   :container => {
#     :image => 'my-service:1.0',
#     :type => 'DOCKER'
#   },
#   :env => {
#     'TEMPORARY_TOKEN' => temp
#   },
#   :instances => 1
# })

# launched applications know to use temporary token to access permanent token,
# which can then be used to access secrets. using temp token to access permanent
# token exhausts the num_uses, making it worthless, so it's ok that it's visible
# as environment variable in application process

# code below represents launched application code:
puts "-- launched application using temp token to access permanent token".green

# irl, app code would access 'temp' token via ENV
app_temp_client = Vault::Client.new(address: vault_address, token: temp)
# get the permanent token to use to grab real secrets
puts "using temporary token #{temp} to access permanent token"
perm_token = app_temp_client.logical.read("cubbyhole/app-token")[:data][:token]

# app creates vault client with real token
puts "using permanent token #{perm_token} to access db password"
app_perm_client = Vault::Client.new(address: vault_address, token: perm_token)

# app reads real secret
secret_password = app_perm_client.logical.read("secret/my-service-db-password")[:data][:password]

puts "accessed secret database password '#{secret_password}' without no disk!"

# what if malicious person or process tries to get permanent token:
puts "-- malicious process now trying to access permanent token with temp token:".green
malicious_temp_client = Vault::Client.new(address: vault_address, token: temp)
# get the permanent token to use to grab real secrets
begin
  app_temp_client.logical.read("cubbyhole/app-token")[:data][:token]
rescue Vault::HTTPClientError => error
  puts "sorry malicious process! num_uses exhausted!".red
  puts "reading token failed -> #{error.message}"
end
