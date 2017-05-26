require 'sinatra'
require 'sinatra/reloader' if development?
require 'sinatra/content_for'
require 'tilt/erubis'

configure do
  enable :sessions
  set :session_secret, 'secret' # normally set by env variable
  set :erb, escape_html: true
end

# Return an error message if the name is invalid. Return nil otherwise.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    'List name must be between 1 and 100 characters.'
  elsif session[:lists].any? { |list| list[:name] == name }
    'List name must be unique'
  end
end

# Return an error if the name is invalid. Return nil otherwise.
def error_for_task_name(name)
  unless (1..100).cover? name.size
    'Task name must be between 1 and 100 characters.'
  end
end

# Redirects if list is invalid
def validate_list(list_id)
  unless @lists.any? { |list| list[:id] == list_id }
    session[:error] = "Whaaaat? There's no list there. That's crazy!"
    redirect '/lists'
  end
end

# generates id for new element
def next_element_id(elements)
  max = elements.map { |element| element[:id] }.max || 0
  max + 1
end

helpers do
  # Check if all todos on a list are done
  def all_done?(list_id)
    list = @lists.find { |this_list| this_list[:id] == list_id }
    !list[:todos].empty? && list[:todos].all? { |todo| todo[:completed] }
  end

  # Return a string of the pattern "Remaining tasks / Total tasks"
  def remaining(list)
    total = list[:todos].size
    remaining = list[:todos].count { |todo| !todo[:completed] }
    "#{remaining}/#{total}"
  end

  # Assigns the "complete" class to completed lists
  def list_class(list_id)
    'complete' if all_done?(list_id)
  end

  # Yields an array of lists sorted by completeness to the block
  def sort_lists(lists)
    incomplete, complete = lists.partition { |list| all_done?(list[:id]) }
    complete.each { |list| yield list, list[:id] }
    incomplete.each { |list| yield list, list[:id] }
  end

  # Yields an array of todos sorted by completeness to the block
  def sort_todos(todos)
    incomplete, complete = todos.partition { |todo| todo[:completed] }
    complete.each { |todo| yield todo, todo[:id] }
    incomplete.each { |todo| yield todo, todo[:id] }
  end
end

before do
  session[:lists] ||= []
  @lists = session[:lists]
end

get '/' do
  redirect '/lists'
end

# view all of the lists
get '/lists' do
  erb :lists, layout: :layout
end

# render new list form
get '/lists/new' do
  erb :new_list, layout: :layout
end

# Create a new list
post '/lists' do
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    list_id = next_element_id(@lists)
    session[:lists] << { id: list_id, name: list_name, todos: [] }
    session[:success] = 'The list has been created.'
    redirect '/lists'
  end
end

# display list and tasks
get '/lists/:list_id' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @list = @lists.find { |list| list[:id] == @list_id }
  @todos = @list[:todos]
  erb :view_list, layout: :layout
end

# Edit an existing todo list
get '/lists/:list_id/edit' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @list_name = @lists.find { |list| list[:id] == @list_id }[:name]
  erb :edit_list, layout: :layout
end

# update an existing todo list
post '/lists/:list_id' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @list = @lists.find { |list| list[:id] == @list_id }
  @list_name = @list[:name]
  new_name = params[:list_name].strip
  error = error_for_list_name(new_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    @list[:name] = new_name
    session[:success] = 'The list has been renamed.'
    redirect "/lists/#{@list_id}"
  end
end

# delete a todo list
post '/lists/:list_id/delete' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @lists.delete_if { |list| list[:id] == @list_id }
  session[:success] = 'The list has been deleted.'
  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    "/lists"
  else
    redirect '/lists'
  end
end

# add a task to a todo list
post '/lists/:list_id/todos' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @list = @lists.find { |list| list[:id] == @list_id }
  @list_name = @list[:name]
  error = error_for_task_name(params[:todo].strip)
  if error
    @todos = @list[:todos]
    session[:error] = error
    erb :view_list, layout: :layout
  else
    id = next_element_id(@list[:todos])
    @list[:todos] << { id: id, name: params[:todo], completed: false }
    session[:success] = "There's a new task! Hoooorah!"
    redirect "/lists/#{@list_id}"
  end
end

# delete a task from a todo list
post '/lists/:list_id/todos/delete/:todo_id' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @list = @lists.find { |list| list[:id] == @list_id }
  todo_id = params[:todo_id].to_i
  @list[:todos].delete_if { |todo| todo[:id] == todo_id }
  if env['HTTP_X_REQUESTED_WITH'] == 'XMLHttpRequest'
    status 204
  else
    session[:success] = 'What task? There was a task there? I remember no task.'
    redirect "/lists/#{@list_id}"
  end
end

# toggle task to incomplete
post '/lists/:list_id/todos/:task_id/false' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @task_id = params[:task_id].to_i
  @list = @lists.find { |list| list[:id] == @list_id }
  @task = @list[:todos].find { |task| task[:id] == @task_id }
  @task[:completed] = false
  session[:success] = 'Still gotta do that one!'
  redirect "/lists/#{@list_id}"
end

# toggle task to complete
post '/lists/:list_id/todos/:task_id/true' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @list = @lists.find { |list| list[:id] == @list_id }
  @task_id = params[:task_id].to_i
  @task = @list[:todos].find { |task| task[:id] == @task_id }
  @task[:completed] = true
  session[:success] = 'That task is dooooone! Buhbye task!'
  redirect "/lists/#{@list_id}"
end

# Mark all of a lists' todos as complete'
post '/lists/:list_id/todos/complete_all' do
  @list_id = params[:list_id].to_i
  validate_list(@list_id)
  @list = @lists.find { |list| list[:id] == @list_id }
  @list[:todos].each { |todo| todo[:completed] = true }
  session[:success] = 'You did them all! Hoooraaaay!'
  redirect "/lists/#{@list_id}"
end
