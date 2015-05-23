require 'sinatra'

class MyApp < Sinatra::Base
  get '/' do
    "zomg!"
  end
end

app = lambda do |env|
  status = 200
  headers = {
    'Content-Type' => 'application/json',
    'Content-Length' => '8',
  }
  body = ['{"a": 1}']
  [status, headers, body]
end

run(app)
