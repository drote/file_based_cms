ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'rack/test'
require 'erb'

require_relative '../fb_cms'

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = '')
    File.open(File.join(data_path, name), 'w') do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    {'rack.session' => { signed_in_as: 'admin' } }
  end

  def logged_out_default_message
    'You must be signed in to do that.'
  end

  def test_index
    create_document 'about.md'
    create_document 'changes.txt'

    get '/'
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, 'about.md'
    assert_includes last_response.body, 'changes.txt'
  end

  def test_txt_file_page
    test_text = "['WED', '9/12/2018', '10:05AM'] => STARTING INITIAL DESIGN DRAFT."
    create_document 'history.txt', test_text

    get '/history.txt'

    assert_equal 200, last_response.status
    assert_equal 'text/plain', last_response['Content-Type']

    assert_includes last_response.body, test_text
  end

  def test_md_file_page
    create_document 'about.md', 'File based CMS'
    test_text = '<p>File based CMS</p>'

    get '/about.md'
    assert_equal 200, last_response.status
    assert_equal 'text/html;charset=utf-8', last_response['Content-Type']
    assert_includes last_response.body, test_text
  end

  def test_messages_appears_only_once
    get '/', {}, {'rack.session' => { message: 'helpful message' } }
    assert_includes last_response.body, 'helpful message'
    assert_nil session[:message]
  end

  def test_nonexistent_file
    error_text = 'wrongfilename.ext does not exist'

    get '/wrongfilename.ext'
    assert_equal 302, last_response.status
    assert_equal error_text, session[:message]
  end

  def test_edit_page
    create_document 'changes.txt'

    get '/changes.txt/edit', {}, admin_session
    assert_equal 200, last_response.status

    assert_includes last_response.body, 'Edit content of changes.txt'
    assert_includes last_response.body, %q(action="/changes.txt" method="post">)
  end

  def test_edit_form_signed_out
    create_document 'about.md'
    create_document 'changes.txt'

    get '/about.md/edit'
    assert_equal 302, last_response.status
    assert_equal logged_out_default_message, session[:message]
  end

  def test_edit_post
    create_document 'changes.txt'

    post '/changes.txt', {edited_content: 'new content'}, admin_session

    assert_equal 302, last_response.status
    assert_equal 'changes.txt has been updated', session[:message]

    get last_response['Location']
    assert_equal 200, last_response.status

    get '/changes.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'new content'
  end

  def test_edit_post_signed_out
    create_document 'about.md'
    create_document 'changes.txt'

    post '/changes.txt', {edited_content: 'new content'}
    assert_equal 302, last_response.status
    assert_equal logged_out_default_message, session[:message]

    get '/changes.txt'
    refute_includes last_response.body, 'new content'
  end

  def text_edit_nonexistent_page
    error_text = 'wrongfilename.ext does not exist'

    get '/wrongfilename.ext/edit', {}, admin_session
    assert_equal 302, last_response.status
    assert_equal error_text, session[:message]

    get last_response['Location']
    assert_equal 200, last_response.status
  end

  def test_new_file_form
    get '/new', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<input'
    assert_includes last_response.body, %q(<form action="/new" method="post">)
  end

  def test_new_doc_form_signed_out
    get '/new'
    assert_equal 302, last_response.status
    assert_equal logged_out_default_message, session[:message]
  end

  def test_new_doc_post
    post '/new', {new_document: 'new_document.txt'}, admin_session
    assert_equal 302, last_response.status
    assert_equal 'new_document.txt has been created', session[:message]

    get last_response['Location']
    assert_includes last_response.body, 'new_document.txt'
  end

  def test_new_doc_post_signed_out
    post '/new', {new_document: 'new_document.txt'}
    assert_equal 302, last_response.status
    assert_equal logged_out_default_message, session[:message]

    get last_response['Location']
    refute_includes last_response.body, 'new_document.txt'
  end

  def test_new_file_without_name
    post '/new', {new_document: ''}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'A name is required'
  end

  def test_new_file_invalid_extension
    post '/new', {new_document: 'noextension'}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid file type'
  end

  def test_delete_button
    create_document 'about.md'
    create_document 'changes.txt'

    post '/about.md/delete', {}, admin_session
    assert_equal 302, last_response.status
    assert_equal 'about.md was deleted', session[:message]

    refute_includes last_response.body, %q(href=''/about.md'')
  end

  def test_delete_button_signed_out
    create_document 'about.md'
    create_document 'changes.txt'

    post 'changes.txt/delete'
    assert_equal 302, last_response.status
    assert_equal logged_out_default_message, session[:message]

    get last_response['Location']
    assert_includes last_response.body, %q(<a href="/changes.txt")
  end

  def test_delete_nonexistent_file
    create_document 'about.md'
    create_document 'changes.txt'

    post 'nofile.txt/delete', {}, admin_session
    assert_equal 302, last_response.status
    assert_equal 'nofile.txt does not exist', session[:message]
  end

  def test_signin_form
    get '/users/signin'
    assert_equal 200, last_response.status
    assert_includes last_response.body,  %q(<form action="/users/signin" method="post">)
  end

  def test_sign_in
    post '/users/signin', username: 'admin', password: 'secret'
    assert_equal 302, last_response.status
    assert_equal 'Welcome!', session[:message]
    assert_equal 'admin', session[:signed_in_as]

    get last_response['Location']
    assert_includes last_response.body, 'You are logged in as admin'
  end

  def test_sign_in_bad_credentials
    post '/users/signin', username: 'notauser', password: 'notapassword'
    assert_equal 422, last_response.status
    assert_nil session[:signed_in_as]
    assert_includes last_response.body, 'Invalid Credentials'
    assert_includes last_response.body, 'notauser'
  end

  def test_sign_out
    get '/', {}, admin_session
    assert_includes last_response.body, 'You are logged in as admin'

    post '/users/signout'

    get last_response['Location']
    assert_equal 200, last_response.status
    assert_nil session[:signed_in_as]
    assert_includes last_response.body, 'You have been signed out'
    assert_includes last_response.body, 'Sign In'
  end

  def test_duplicate_button
    create_document 'about.md'
    create_document 'changes.txt'

    post '/about.md/duplicate', {}, admin_session
    assert_equal 302, last_response.status
    assert_equal 'about.md has been duplicated', session[:message]

    get last_response['Location']
    assert_includes last_response.body, %q(href="/about_copy1.md")
  end

  def test_duplicate_button_multiple_copies
    create_document 'about.md'
    create_document 'about.md_copy1'
    create_document 'about.md_copy2'
    create_document 'about.md_copy3'
    create_document 'about.md_copy4'
    create_document 'changes.txt'

    post '/about.md/duplicate', {}, admin_session

    get last_response['Location']
    assert_includes last_response.body, %q(href="/about_copy5.md")
  end

  def test_duplicated_button_signed_out
    create_document 'about.md'
    create_document 'changes.txt'

    post 'changes.txt/duplicate'
    assert_equal 302, last_response.status
    assert_equal logged_out_default_message, session[:message]

    get last_response['Location']
    refute_includes last_response.body, %q(<a href='/changes_copy1.txt')
  end

  def test_duplicate_nonexistent_file
    create_document 'about.md'
    create_document 'changes.txt'

    post 'nofile.txt/duplicate', {}, admin_session
    assert_equal 302, last_response.status
    assert_equal 'nofile.txt does not exist', session[:message]
  end

  def test_image_upload_form
    get '/new_image', {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<form action="/new_image" method="post">)
  end

  def test_image_upload_signed_out
    get '/new_image'
    assert_equal 302, last_response.status
    assert_equal logged_out_default_message, session[:message]
  end

  def test_image_upload_post
    post '/new_image', {new_image: '1.jpg', image_description: 'image'}, admin_session
    
    assert_equal "Image has been uploaded", session[:message]
    get last_response['Location']
    assert_includes last_response.body, %q(<a href="/1.md")

    get '/1.md'

    assert_includes last_response.body, %q(<img src="1.jpg" alt="image">)
  end

  def test_image_upload_nonexistent_image
    post '/new_image', {new_image: 'none.jpg', image_description: 'image'}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Image cannot be found.'
  end

  def test_image_upload_no_description
    post '/new_image', {new_image: '1.jpg', image_description: ''}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Description cannot be empty.'
  end

  def test_image_invalid_type
    post '/new_image', {new_image: '1.pdf', image_description: 'image'}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid image type.'
  end
end
