require 'fake_sinatra'
require 'rack/test'
require 'stringio'

RSpec.describe FakeSinatra do
  def session_for(app)
    Capybara::Session.new(:rack_test, app)
  end

  def assert_request(app, method, path, assertions, &overrides)
    env = Rack::MockRequest.env_for path, method: method
    overrides.call env if overrides
    status, headers, body = app.call(env)
    assertions.each do |name, expectation|
      case name
      when :body
        expect(body.join).to eq expectation
      when :status
        expect(status).to eq expectation
      when :content_type
        expect(headers['Content-Type']).to eq expectation
      when :location
        expect(headers['Location']).to eq expectation
      else
        raise "Unexpected assertion: #{name.inspect}"
      end
    end
  end

  describe 'routing to a block' do
    it 'routes based on the method (get/post/put/patch/delete)' do
      app = Class.new FakeSinatra::Base do
        get('/')    { 'get request to /'    }
        post('/')   { 'post request to /'   }
        put('/')    { 'put request to /'    }
        patch('/')  { 'patch request to /'  }
        delete('/') { 'delete request to /' }
      end

      assert_request app, :get,    '/', body: 'get request to /'
      assert_request app, :post,   '/', body: 'post request to /'
      assert_request app, :put,    '/', body: 'put request to /'
      assert_request app, :patch,  '/', body: 'patch request to /'
      assert_request app, :delete, '/', body: 'delete request to /'
    end

    it 'routes based on the path' do
      app = Class.new FakeSinatra::Base do
        get('/a') { 'first'  }
        get('/b') { 'second' }
      end

      assert_request app, :get, '/a', body: 'first'
      assert_request app, :get, '/b', body: 'second'
    end

    it 'routes based on both of these together' do
      app = Class.new FakeSinatra::Base do
        get('/a')  { 'first'  }
        get('/b')  { 'second' }
        post('/a') { 'third'  }
        post('/b') { 'fourth' }
      end

      assert_request app, :get,  '/a', body: 'first'
      assert_request app, :post, '/a', body: 'third'

      assert_request app, :get,  '/b', body: 'second'
      assert_request app, :post, '/b', body: 'fourth'
    end

    it 'returns a 404 when it can\'t find a match' do
      app = Class.new(FakeSinatra::Base) { get('/a') { '' } }
      assert_request app, :get, '/a', status: 200
      assert_request app, :get, '/b', status: 404
    end
  end

  describe 'routed code' do
    it 'returns the result as the body' do
      app = Class.new(FakeSinatra::Base) { get('/') { 'the body' } }
      assert_request app, :get, '/', body: 'the body'
    end

    it 'has an empty body if the block evaluates to a non-string' do
      app = Class.new(FakeSinatra::Base) { get('/') { } }
      assert_request app, :get, '/', body: ''
    end
  end

  describe 'the block of code' do
    it 'defaults the content-type to text/html, but allows it to be overridden' do
      app = Class.new FakeSinatra::Base do
        get('/a') { }
        get('/b') { content_type 'text/plain' }
      end

      assert_request app, :get, '/a', content_type: 'text/html'
      assert_request app, :get, '/b', content_type: 'text/plain'
    end


    it 'allows the status to be set' do
      app = Class.new FakeSinatra::Base do
        get('/a') { }
        get('/b') { status 400 }
      end

      assert_request app, :get, '/a', status: 200
      assert_request app, :get, '/b', status: 400
    end

    it 'has access to the params' do
      app = Class.new FakeSinatra::Base do
        get('/a') { "params: #{params.inspect}" }
      end
      assert_request app, :get, '/a?b=c', body: 'params: {"b"=>"c"}'
    end

    it 'has a convenience method "redirect", which sets the status, location, and halts execution' do
      app = Class.new FakeSinatra::Base do
        get('/a') do
          redirect 'http://www.example.com'
          raise "should not get here"
        end
      end

      assert_request app, :get, '/a', status: 302, location: 'http://www.example.com', body: ''
    end
  end

  it 'gives access to the env' do
    app = Class.new FakeSinatra::Base do
      get('/a') { "REQUEST_METHOD: #{env['REQUEST_METHOD']}" }
    end
    assert_request app, :get, '/a?b=c&d=e', body: 'REQUEST_METHOD: GET'
  end

  describe 'params' do
    describe 'parsing params with a Content-Type of application/x-www-form-urlencoded' do
      def assert_parses(urlencoded, expected)
        actual = FakeSinatra::Base.parse_urlencoded_params(urlencoded)
        expect(actual).to eq expected
      end

      it 'splits them on "&"' do
        assert_parses 'a=b&c=d', {'a' => 'b', 'c' => 'd'}
      end

      it 'splits keys and values on the first "="' do
        assert_parses 'a=b=c', {'a' => 'b=c'}
      end
    end

    it 'includes query parms' do
      app = Class.new FakeSinatra::Base do
        get('/a') { "params: #{params.inspect}" }
      end
      assert_request app, :get, '/a?b=c&d=e', body: 'params: {"b"=>"c", "d"=>"e"}'
    end

    context 'from form data' do
      let(:app) do
        Class.new FakeSinatra::Base do
          get('/a')  { "params: #{params.inspect}" }
          post('/a') { "params: #{params.inspect}" }
        end
      end

      it 'does not read the form data when the request is GET' do
        assert_request app, :get, '/a', body: 'params: {}' do |env|
          env['CONTENT_TYPE']      = 'application/x-www-form-urlencoded'
          env['CONTENT_LENGTH']    = '7'
          env['rack.input'].string = 'a=1'
        end
      end

      it 'does not read the form data when the CONTENT_TYPE is not application/x-www-form-urlencoded' do
        assert_request app, :post, '/a', body: 'params: {}' do |env|
          env['CONTENT_TYPE']      = 'application/json'
          env['CONTENT_LENGTH']    = '7'
          env['rack.input'].string = 'a=1'
        end
      end

      it 'does not read the form data when there is no CONTENT_LENGTH' do
        assert_request app, :post, '/a', body: 'params: {}' do |env|
          env['CONTENT_TYPE']      = 'application/x-www-form-urlencoded'
          env['CONTENT_LENGTH']    = nil
          env['rack.input'].string = 'a=1'
        end
      end

      it 'only reads the form data as far as the CONTENT_LENGTH says it should' do
        assert_request app, :post, '/a', body: 'params: {"b"=>"c", "d"=>"e"}' do |env|
          env['CONTENT_TYPE']      = 'application/x-www-form-urlencoded'
          env['CONTENT_LENGTH']    = '7'
          env['rack.input'].string = "b=c&d=eTHIS IS NOT READ"
        end
      end
    end

    it 'returns nil if the param doesn\'t exist' do
      app = Class.new FakeSinatra::Base do
        get('/') { "nonexistent: #{params['nonexistent'].inspect}" }
      end
      assert_request app, :get, '/', body: 'nonexistent: nil'
    end

    it 'allows the params to be accessed with a string or a symbol' do
      app = Class.new FakeSinatra::Base do
        get('/') { "#{params['key']} #{params[:key]}" }
      end
      assert_request app, :get, '/?key=value', body: 'value value'
    end
  end
end
