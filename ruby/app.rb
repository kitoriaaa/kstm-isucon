require 'sinatra/base'
require 'mysql2'
require 'mysql2-cs-bind'
require 'erubis'

module Ishocon1
  class AuthenticationError < StandardError; end
  class PermissionDenied < StandardError; end
end

class Ishocon1::WebApp < Sinatra::Base
  session_secret = ENV['ISHOCON1_SESSION_SECRET'] || 'showwin_happy'
  use Rack::Session::Cookie, key: 'rack.session', secret: session_secret
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../public', __FILE__)
  set :protection, true

  helpers do
    def config
      @config ||= {
        db: {
          host: ENV['ISHOCON1_DB_HOST'] || 'localhost',
          port: ENV['ISHOCON1_DB_PORT'] && ENV['ISHOCON1_DB_PORT'].to_i,
          username: ENV['ISHOCON1_DB_USER'] || 'ishocon',
          password: ENV['ISHOCON1_DB_PASSWORD'] || 'ishocon',
          database: ENV['ISHOCON1_DB_NAME'] || 'ishocon1'
        }
      }
    end

    def db
      return Thread.current[:ishocon1_db] if Thread.current[:ishocon1_db]
      client = Mysql2::Client.new(
        host: config[:db][:host],
        port: config[:db][:port],
        username: config[:db][:username],
        password: config[:db][:password],
        database: config[:db][:database],
        reconnect: true
      )
      client.query_options.merge!(symbolize_keys: true)
      Thread.current[:ishocon1_db] = client
      client
    end

    def time_now_db
      Time.now - 9 * 60 * 60
    end

    def authenticate(email, password)
      user = db.xquery('SELECT * FROM users WHERE email = ?', email).first
      fail Ishocon1::AuthenticationError unless user.nil? == false && user[:password] == password
      session[:user_name] = user[:name]
      session[:user_id] = user[:id]
    end

    def authenticated!
      fail Ishocon1::PermissionDenied unless current_user
    end

    def current_user
      return unless session[:user_id] && session[:user_name]
      {
        :name => session[:user_name],
        :id => session[:user_id]
      }
    end

    def update_last_login(user_id)
      db.xquery('UPDATE users SET last_login = ? WHERE id = ?', time_now_db, user_id)
    end

    def buy_product(product_id, user_id)
      db.xquery('INSERT INTO histories (product_id, user_id, created_at) VALUES (?, ?, ?)', \
        product_id, user_id, time_now_db)
    end

    def already_bought?(product_id)
      return false unless current_user
      count = db.xquery('SELECT count(*) as count FROM histories WHERE product_id = ? AND user_id = ?', \
                        product_id.to_i, current_user[:id].to_i).first[:count]
      count > 0
    end

    def create_comment(product_id, user_id, content)
      db.xquery('INSERT INTO comments (product_id, user_id, content, created_at) VALUES (?, ?, ?, ?)', \
        product_id, user_id, content, time_now_db)
    end
  end

  error Ishocon1::AuthenticationError do
    session[:user_id] = nil
    halt 401, erb(:login, layout: false, locals: { message: '?????????????????????????????????' })
  end

  error Ishocon1::PermissionDenied do
    halt 403, erb(:login, layout: false, locals: { message: '???????????????????????????????????????' })
  end

  get '/login' do
    session.clear
    erb :login, layout: false, locals: { message: 'EC??????????????????????????????????????????' }
  end

  post '/login' do
    authenticate(params['email'], params['password'])
    # update_last_login(current_user[:id])
    redirect '/'
  end

  get '/logout' do
    session[:user_id] = nil
    session.clear
    erb :login, layout: false, locals: { message: 'EC??????????????????????????????????????????' }
    # redirect '/login'
  end

  get '/' do
    page = params[:page].to_i || 0
    now_offset = page*50
    products = db.xquery("SELECT * FROM products WHERE ? >= id AND id > ? ORDER BY id DESC", 10000-now_offset, 10000-now_offset-50)
    id_list = products.map { |item| item[:id] }
    cmt_query = <<SQL
SELECT *
FROM comments as c
INNER JOIN users as u
ON c.user_id = u.id
WHERE 
c.product_id IN (#{id_list.join(',')})
ORDER BY c.created_at DESC
SQL
    cmt = db.query(cmt_query)

    erb :index, locals: { products: products, cmt: cmt}
  end

  get '/users/:user_id' do
    products_query = <<SQL
SELECT p.id, p.name, SUBSTRING(p.description, 1, 71) as description, p.image_path, p.price, h.created_at
FROM histories as h
LEFT OUTER JOIN products as p
ON h.product_id = p.id
WHERE h.user_id = ?
ORDER BY h.id DESC
LIMIT 30
SQL
    products = db.xquery(products_query, params[:user_id].to_i)

    total_pay = db.xquery('SELECT SUM(p.price) as total FROM histories as h INNER JOIN products as p ON h.product_id = p.id WHERE h.user_id = ?', params[:user_id].to_i).first

    user = db.xquery('SELECT id, name FROM users WHERE id = ?', params[:user_id].to_i).first
    erb :mypage, locals: { products: products, user: user, total_pay: total_pay[:total] }
  end

  get '/products/:product_id' do
    product = db.xquery('SELECT * FROM products WHERE id = ?', params[:product_id].to_i).first
    erb :product, locals: { product: product }
  end

  post '/products/buy/:product_id' do
    authenticated!
    buy_product(params[:product_id], current_user[:id])
    redirect "/users/#{current_user[:id]}"
  end

  post '/comments/:product_id' do
    authenticated!
    create_comment(params[:product_id], current_user[:id], params[:content])
    redirect "/users/#{current_user[:id]}"
  end

  get '/initialize' do
    db.query('DELETE FROM users WHERE id > 5000')
    db.query('DELETE FROM products WHERE id > 10000')
    db.query('DELETE FROM comments WHERE id > 200000')
    db.query('DELETE FROM histories WHERE id > 500000')
    "Finish"
  end
end
