require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"

configure do
  enable :sessions
  set :session_secret, 'secret' #normally would be set by session variable not in code
end

# Return an error message if the name is invalid. Return nil otherwise.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    "List name must be between 1 and 100 characters."
  elsif session[:lists].any? {|list| list[:name] == name }
    "List name must be unique"
  end
end

def error_for_task_name(name)
  if !(1..100).cover? name.size
    "Task name must be between 1 and 100 characters."
  end
end

helpers do
  def all_done?(list_id)
    todos = @lists[list_id][:todos]
    !todos.empty? && todos.all? {|todo| todo[:completed] }
  end

  def remaining(list)
    total = list[:todos].size
    remaining = list[:todos].count {|todo| !todo[:completed] }
    "#{remaining}/#{total}"
  end

  def list_class(list_id)
    "complete" if all_done?(list_id)
  end

  def sort_lists(lists, &block)
    scored = scored_hash(lists) do |_, idx|
      all_done?(idx)
    end

    each_by_score(scored) { |list, idx| yield list, idx }
  end

  def sort_todos(todos, &block)
    scored = scored_hash(todos) do |todo, _|
      todo[:completed]
    end

    each_by_score(scored) { |todo, idx| yield todo, idx }
  end

  def scored_hash(arr, &block)
    arr.map.with_index do |item, idx|
      score = yield(item, idx) ? 1 : 0
      {item: item, idx: idx, score: score}
    end
  end

  def each_by_score(scored_arr, &block)
    scored_arr.sort_by {|list| list[:score] }.each do |list|
      yield list[:item], list[:idx] 
    end
  end
end

before do
  session[:lists] ||= []
  @lists = session[:lists]
end

get "/" do
  redirect "/lists"
end

# view all of the lists
get "/lists" do
  erb :lists, layout: :layout
end

# render new list form
get "/lists/new" do
  erb :new_list, layout: :layout
end

# Create a new list 
post "/lists" do
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)
  if error
    session[:error] = error
    erb :new_list, layout: :layout
  else
    session[:lists] << {name: list_name, todos: []}
    session[:success] = "The list has been created."
    redirect "/lists"
  end
end

# display list and tasks
get "/lists/:list_id" do
  @list_id = params[:list_id].to_i
  @list_name = @lists[@list_id][:name]
  @todos = @lists[@list_id][:todos]
  erb :view_list, layout: :layout
end

# Edit an existing todo list
get "/lists/:list_id/edit" do
  @list_id = params[:list_id].to_i
  @list_name = @lists[@list_id][:name]
  erb :edit_list, layout: :layout
end

# update an existing todo list
post "/lists/:list_id" do
  
  @list_id = params[:list_id].to_i
  @list_name = @lists[@list_id][:name]
  new_name = params[:list_name].strip
  error = error_for_list_name(new_name)
  if error
    session[:error] = error
    erb :edit_list, layout: :layout
  else
    session[:lists][@list_id][:name] = new_name
    session[:success] = "The list has been renamed."
    redirect "/lists/#{@list_id}"
  end
end

# delete a todo list
post "/lists/:list_id/delete" do
  @lists.delete_at(params[:list_id].to_i)
  session[:success] = "The list has been deleted."
  redirect "/lists"
end


# add a task to a todo list
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  @list_name = @lists[@list_id][:name]
  error = error_for_task_name(params[:todo].strip)
  if error
    @todos = @lists[@list_id][:todos]
    session[:error] = error
    erb :view_list, layout: :layout
  else
    @lists[@list_id][:todos] << {name: params[:todo], completed: false}
    session[:success] = "There's a new task! Hoooorah!"
    redirect "/lists/#{@list_id}"
  end
end

# delete a task from a todo list
post "/lists/:list_id/todos/delete/:todo_id" do
  @list_id = params[:list_id].to_i
  todo_id = params[:todo_id].to_i
  @lists[@list_id][:todos].delete_at(todo_id)
  session[:success] = "What task? There was a task there? I remember no task."
  redirect "/lists/#{@list_id}"
end

# toggle task to incomplete
post "/lists/:list_id/todos/:task_id/false" do
  @list_id = params[:list_id].to_i
  @task_id = params[:task_id].to_i
  @task = @lists[@list_id][:todos][@task_id]
  @task[:completed] = false
  session[:success] = "Still gotta do that one!"
  redirect "/lists/#{@list_id}"
end

# toggle task to complete
post "/lists/:list_id/todos/:task_id/true" do
  @list_id = params[:list_id].to_i
  @task_id = params[:task_id].to_i
  @task = @lists[@list_id][:todos][@task_id]
  @task[:completed] = true
  session[:success] = "That task is dooooone! Buhbye task!"
  redirect "/lists/#{@list_id}"
end

# Mark all of a lists' todos as complete'
post "/lists/:list_id/todos/complete_all" do
  @list_id = params[:list_id].to_i
  @lists[@list_id][:todos].each {|todo| todo[:completed] = true}
  session[:success] = "You did them all! Hoooraaaay!"
  redirect "/lists/#{@list_id}"
end