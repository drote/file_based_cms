require 'redcarpet'
require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'yaml'
require 'bcrypt'
require 'pry'

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

def data_path
  if ENV['RACK_ENV'] == 'test'
    File.expand_path('../test/data', __FILE__)
  else
    File.expand_path('../data', __FILE__)
  end
end

def credential_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path('../test/users.yml', __FILE__)
  else
    File.expand_path('../users.yml', __FILE__)
  end
end

def public_path
  File.expand_path('../public', __FILE__)
end

def valid_extensions
  ['.txt', '.md']
end

def valid_image_extensions
  ['.jpg', '.png', '.jpeg']
end

def user_credentials
  YAML.load_file(credential_path)
end

# Fetches the file path, returns error if file does not exist
def fetch_file_path(file_param)
  file_path = File.join(data_path, file_param)

  return file_path if File.exist?(file_path)
  
  session[:message] = "#{file_param} does not exist"
  redirect '/'
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def display_file(path)
  contents = File.read(path)
  ext = File.extname(path)

  case ext
  when ".txt"
    headers['Content-Type'] = 'text/plain'
    contents
  when ".md"
    erb render_markdown(contents)
  end
end

def error_for_file_name(file_name)
  if file_name.length == 0
    'A name is required'
  elsif !valid_extensions.include?(File.extname(file_name))
    "Invalid file type" + 
    "\n(Currently accepting: #{valid_extensions.join(', ')}.)"
  elsif all_files.include?(file_name)
    "#{file_name} exists allready!"
  else
    false
  end
end

def error_for_new_user_name(username)
  if username.length < 4
    'User name must be at least 4 characters long.'
  elsif user_credentials.key?(username)
    'This user name exists already, please choose a different one.'
  end
end

def error_for_new_password(password)
  if password.length < 4
    'Password must be at least 4 characters long.'
  end
end

def error_for_new_image(name, desc)
  if !File.exist?(File.join(public_path, name))
    'Image cannot be found.'
  elsif desc.length == 0 
    'Description cannot be empty.'
  elsif !valid_image_extensions.include?(File.extname(name))
    'Invalid image type.' +
    "Currently accepting: #{valid_image_extensions.join(',')}."
  end
end

def signed_in?
  session.key?(:signed_in_as)
end

def require_signed_in_user
  unless signed_in?
    session[:message] = 'You must be signed in to do that.'
    redirect '/'
  end
end

def require_signed_out_user
  if signed_in?
    session[:message] = 'You are signed in already!'
    redirect '/'
  end
end

def valid_credentials(user, pass)
  pass_in_db = user_credentials[user]
  user_credentials.key?(user) && BCrypt::Password.new(pass_in_db) == pass
end

# strips filename of copy numbers and extensions
def base_file_name(file)
  file.split('.')[0].split('_copy')[0]
end

# returns copy number of file as integer
def copy_number(file)
  (file.split('_copy')[1] || 0).to_i
end

def next_copy_number(filename)
  all_files.select do |file|
    base_file_name(file) == filename
  end.map { |file| copy_number(file) }.max + 1
end

def create_duplicate_file_name(file_name)
  name, ext = file_name.split('.')
  name = name.split('_copy')[0]
  "#{name}_copy#{next_copy_number(name)}.#{ext}"
end

def all_files
  pattern = File.join(data_path, "*")
  Dir.glob(pattern).map do |file| 
    File.basename(file)
  end
end

# Displays the contents of the Data folder
get '/' do
  @files = all_files.sort
  erb :index
end

get '/new' do
  require_signed_in_user

  erb :new
end

post '/new' do
  require_signed_in_user

  new_file_name = params[:new_document].strip

  error = error_for_file_name(new_file_name)
  if error
    session[:message] = error
    status 422
    erb :new
  else
    FileUtils.touch(File.join(data_path, new_file_name))
    session[:message] = "#{new_file_name} has been created"
    redirect '/'
  end
end

get '/new_image' do
  require_signed_in_user

  erb :new_image
end

post '/new_image' do
  require_signed_in_user
  image_name = params[:new_image]
  image_description = params[:image_description]

  error = error_for_new_image(image_name, image_description)

  if error
    status 422
    session[:message] = error
    erb :new_image
  else
    image_file = File.join(data_path, base_file_name(image_name) + '.md')

    File.open(image_file, 'w') do |file|
      file.write("![#{image_description}](#{image_name})")
    end

    session[:message] = 'Image has been uploaded'
    redirect '/'
  end
end

# Displayes a file from the URL
get '/:file_name' do
  if params[:file_name].include?('.')
    file_path = fetch_file_path(params[:file_name])
    display_file(file_path)
  else
    raise Sinatra::NotFound
  end
end

# Edit file form
get '/:file_name/edit' do
  require_signed_in_user

  file_path = fetch_file_path(params[:file_name])

  @file_name = File.basename(file_path)
  @file_contents = File.read(file_path)

  erb :edit_file
end

# Post request to edit a file
post '/:file_name' do
  require_signed_in_user

  file_path = fetch_file_path(params[:file_name])

  file = File.open(file_path, 'w')
  file << params[:edited_content]
  file.close

  session[:message] = "#{File.basename(file_path)} has been updated"
  redirect "/"
end

# Post request to delete file
post '/:file_name/delete' do
  require_signed_in_user

  file_path = fetch_file_path(params[:file_name])
  FileUtils.rm(file_path)

  session[:message] = "#{File.basename(file_path)} was deleted"
  redirect '/'
end

post '/:file_name/duplicate' do
  require_signed_in_user

  file_path = fetch_file_path(params[:file_name])
  new_file_name = create_duplicate_file_name(params[:file_name])
  copy_path = File.join(data_path, new_file_name)

  FileUtils.cp(file_path, copy_path)

  session[:message] = "#{File.basename(file_path)} has been duplicated"
  redirect '/'
end

get '/users/signin' do
  require_signed_out_user
  erb :sign_in
end

post '/users/signin' do
  require_signed_out_user
  user_name = params[:username]

  if valid_credentials(user_name, params[:password])
    session[:signed_in_as] = user_name
    session[:message] = "Welcome!"
    redirect '/'
  else
    session[:message] = "Invalid Credentials" if (params[:username] || params[:password])
    status 422
    erb :sign_in
  end
end

post '/users/signout' do
  require_signed_in_user
  session.delete(:signed_in_as)
  session[:message] = "You have been signed out"
  redirect '/'
end

get '/users/new' do
  require_signed_out_user
  erb :sign_up
end

post '/users/new' do
  require_signed_out_user

  new_uname = params[:new_username]
  new_pass = params[:new_password]

  error = error_for_new_user_name(new_uname) || error_for_new_password(new_pass)
  if error
    session[:message] = error
    erb :sign_up
  else
    hashed_pass = BCrypt::Password.create(new_pass)
    File.open(credential_path, 'a') do |file|
      file.write "\n"
      file.write "#{new_uname}: #{hashed_pass}"
    end
    session[:message] = 'User created succesfuly!'
    redirect '/'
  end
end

not_found do
  status 404
  erb :page_not_found
end