require "sinatra"
require "mogli"
require "data_mapper"

enable :sessions
set :raise_errors, false
set :show_exceptions, false

DataMapper::Logger.new($stdout, :debug)
if settings.environment == :production and ENV["HEROKU_POSTGRESQL_PINK_URL"]
  DataMapper::setup(:default, ENV["HEROKU_POSTGRESQL_PINK_URL"])
else
  DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/willdo.db")
end
class Task
  include DataMapper::Resource
  property :id, Serial
  property :username, Text, :required => true
  property :taskToComplete, Text, :required => true
  property :cashValue, Integer, :required => true
  property :charityname, Text, :required => true
  property :charityID, Integer, :required => true
  property :created_at, DateTime
  property :updated_at, DateTime
end
DataMapper.finalize.auto_migrate!

# Scope defines what permissions that we are asking the user to grant.
# In this example, we are asking for the ability to publish stories
# about using the app, access to what the user likes, and to be able
# to use their pictures.  You should rewrite this scope with whatever
# permissions your app needs.
# See https://developers.facebook.com/docs/reference/api/permissions/
# for a full list of permissions
FACEBOOK_SCOPE = ''

unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

before do
  # HTTPS redirect
  if settings.environment == :production && request.scheme != 'https'
    redirect "https://#{request.env['HTTP_HOST']}"
  end
end

helpers do
  def check_auth
    # Facebook authentication
    redirect "/auth/facebook" unless session[:at]
    @client = Mogli::Client.new(session[:at])

    # limit queries to 15 results
    @client.default_params[:limit] = 15

    @app  = Mogli::Application.find(ENV["FACEBOOK_APP_ID"], @client)
    @user = Mogli::User.find("me", @client)
  end

  def url(path)
    base = "#{request.scheme}://#{request.env['HTTP_HOST']}"
    base + path
  end

  def post_to_wall_url(message)
    "https://www.facebook.com/dialog/feed?message=#{message}&redirect_uri=#{url("/close")}&display=popup&app_id=#{@app.id}";
  end

  def send_to_friends_url(message)
    "https://www.facebook.com/dialog/send?message=#{message}&redirect_uri=#{url("/close")}&display=popup&app_id=#{@app.id}&link=#{url('/')}";
  end

  def authenticator
    @authenticator ||= Mogli::Authenticator.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], url("/auth/facebook/callback"))
  end

  def first_column(item, collection)
    return ' class="first-column"' if collection.index(item)%4 == 0
  end
end

# the facebook session expired! reset ours and restart the process
error(Mogli::Client::HTTPException) do
  session[:at] = nil
  redirect "/auth/facebook"
end

get "/" do
  check_auth
  erb :index
end

# used by Canvas apps - redirect the POST to be a regular GET
post "/" do
  redirect "/"
end

# used to close the browser window opened to post to wall/send to friends
get "/close" do
  "<body onload='window.close();'/>"
end

get "/auth/facebook" do
  session[:at]=nil
  redirect authenticator.authorize_url(:scope => FACEBOOK_SCOPE, :display => 'page')
end

get '/auth/facebook/callback' do
  client = Mogli::Client.create_from_code_and_authenticator(params[:code], authenticator)
  session[:at] = client.access_token
  redirect '/'
end

post '/create' do
  check_auth
  @task = Task.create(
    :username => @user.name,
    :taskToComplete => params[:taskToComplete],
    :cashValue => params[:cashValue],
    :charityname => params[:charityname],
    :charityID => params[:charityID],
    :created_at => Time.now,
    :updated_at => Time.now
  )
  puts @task.id
  @message = "I will #{@task.taskToComplete} if you will donate #{@task.cashValue.to_s} to #{@task.charityname} <a href=\"https://www.thegivinglab.org/api/donation/start?charityid=#{@task.charityID}&amount=#{@task.cashValue}&donationtype=0\">Accept Challenge and donate</a>!</a>"
  erb :pledge
end

get '/:id' do
  check_auth
  @task = Task.get params[:id]
  if @task
    erb :donate
  else
    redirect '/'
  end
end
