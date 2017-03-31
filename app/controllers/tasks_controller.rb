class TasksController < ApplicationController
  load_and_authorize_resource :only => [:index, :show, :create, :destroy, :update, :new, :edit]
  helper_method :sort_column, :sort_direction
  before_filter :set_per_page_session
  before_action :set_task, only: [:show, :edit, :update, :destroy]
  include TasksHelper

  # GET /tasks
  def index
    set_company_session
    params[:status] = params[:status] || 'active'
    mappings = {active: 'unarchived', archived: 'archived', deleted: 'only_deleted'}
    method = mappings[params[:status].to_sym]
    @tasks = Task.get_tasks(params.merge(get_args(method)))

    respond_to do |format|
      format.js
      format.html # index.html.erb
      format.json { render :json => @tasks }
    end

  end

  # GET /tasks/1
  def show
    redirect_to edit_task_path
  end

  # GET /tasks/new
  def new
    @task = Task.new
  end

  # GET /tasks/1/edit
  def edit
  end

  # POST /tasks
  def create
    company_id = session['current_company'] || current_user.current_company || current_user.first_company_id

    if Task.is_exists?(params[:task][:name], company_id)
      @task_exists = true
      redirect_to(new_task_path, :alert => "Task with same name already exists") unless params[:quick_create]
      return
    end
    @task = Task.new(task_params)
    @task.billable = task_params[:rate].present?
    options = params[:quick_create] ? params.merge(company_ids: company_id) : params
    associate_entity(options, @task)

    respond_to do |format|
      if @task.save
        format.js
        format.json { render :json => @task, :status => :created, :location => @task }
        redirect_to @task, notice: 'Task was successfully created.' unless params[:quick_create]
        return
      else
        format.js
        format.html { render :action => "new" }
        format.json { render :json => @task.errors, :status => :unprocessable_entity }
      end
   end
  end

  # PATCH/PUT /tasks/1
  def update
    if @task.update(task_params)
      associate_entity(params, @task)
      redirect_to @task, notice: 'Task was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /tasks/1
  def destroy
    @task.destroy
    redirect_to tasks_url, notice: 'Task was successfully destroyed.'
  end

  def filter_tasks
    @tasks = Task.filter(params.merge(per: session["#{controller_name}-per_page"])).order(sort_column + " " + sort_direction)
    respond_to { |format| format.js }
  end

  def set_per_page_session
    session["#{controller_name}-per_page"] = params[:per] || session["#{controller_name}-per_page"] || 10
  end

  def bulk_actions
    params[:sort] = params[:sort] || 'created_at'
    result = Services::TaskBulkActionsService.new(params.merge({current_user: current_user})).perform
    @tasks = result[:tasks]
    @message = get_intimation_message(result[:action_to_perform], result[:task_ids])
    @action = result[:action]
    #end
    respond_to { |format| format.js }
  end

  def undo_actions
    params[:archived] ? Task.recover_archived(params[:ids]) : Task.recover_deleted(params[:ids])
    @tasks = Task.unarchived.page(params[:page]).per(session["#{controller_name}-per_page"])
    respond_to { |format| format.js }
  end

  def load_task_data
      task = Task.find_by_id(params[:id]).present? ?  Task.find(params[:id]) : Task.unscoped.find_by_id(params[:id])
      render :text => [task.description || "", task.rate, task.name]
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_task
      @task = Task.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def task_params
      params.require(:task).permit(:name, :description, :billable, :rate)
    end

    def get_intimation_message(action_key, task_ids)
      helper_methods = {archive: 'tasks_archived', destroy: 'tasks_deleted'}
      helper_method = helper_methods[action_key.to_sym]
      helper_method.present? ? send(helper_method, task_ids) : nil
    end

    def sort_column
      params[:sort] ||= 'created_at'
      sort_col = params[:sort]
    end

    def sort_direction
      params[:direction] ||= 'desc'
      %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
    end

    def get_args(status)
      {status: status, per: @per_page, user: current_user, sort_column: sort_column, sort_direction: sort_direction, current_company: session['current_company'], company_id: get_company_id}
    end

end
