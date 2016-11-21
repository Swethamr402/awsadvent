require 'net/http'
require 'json'
require 'io/console'
require 'pp'

puts 'Username:'
user = STDIN.gets.chomp
puts 'Password:'
pw = STDIN.noecho(&:gets).chomp
puts 'Auth0 Organization:'
organization = STDIN.gets.chomp
puts 'Auth0 Client:'
client = STDIN.gets.chomp

# Authenticate to the client with username/password
uri = URI("https://#{organization}.auth0.com/oauth/ro")
req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
req.body = {
  client_id: client,
  username: user,
  password: pw,
  connection: 'adfs',
  grant_type: 'password',
  scope: 'openid'
}.to_json
res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(req)
end

# Use the returned JWT to fetch STS keys
uri = URI("https://#{organization}.auth0.com/delegation")
req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
req.body = {
  client_id: client,
  grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
  id_token: JSON.parse(res.body)['id_token'],
  scope: 'openid',
  api_type: 'aws'
}.to_json

res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
  http.request(req)
end

pp JSON.parse(res.body)['Credentials']
