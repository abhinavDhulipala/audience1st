class ApplicationController < ActionController::Base
  helper :all

  protect_from_forgery

  force_ssl if Rails.env.production?

  include AuthenticatedSystem
  include FilenameUtils

  require 'csv'

  rescue_from ActionController::InvalidAuthenticityToken, :with => :session_expired
  before_action :maintenance_mode?

  private
  def maintenance_mode?
    return unless Option.staff_access_only?
    # allow login/logout even in maint mode
    return if controller_name == 'sessions'
    # allow logged-in staff users
    if current_user.try(:is_staff)
      @gMaintMode = true
    else
      render 'sessions/maintenance'
    end
  end

  public

  # Session keys
  #  :cid               id of logged in user; if absent, nobody logged in
  #  :return_to         route params (for url_for) to return to after valid login
  #  :admin_disabled    admin is logged in but wants to see regular patron view. Causes is_admin, etc to return nil
  #  :checkout_in_progress  true if cart holds valid-looking order, which should be displayed throughout checkout flow
  #  :cart              ID of the order in progress (BUG: redundant with checkout_in_progress??)
  #  :new_session       true when session is created, reset when checking if this is a new session
  #                        (BUG: logic should be moved to the session create logic for interactive login)

  def session_expired
    render :template => 'components/session_expired', :layout => 'application', :status => 400
    true
  end

  # periodically sweep stale orders.  Check is made before every action but only actually
  # does anything every couple of minutes.
  before_action :maybe_run_sweepers

  def maybe_run_sweepers
    StaleOrderSweeper.sweep! if Option.last_sweep > 1.minute.ago
  end

  # set_globals tries to set globals based on current_user, among other things.
  before_action :set_globals

  def set_globals
    @gOrderInProgress = find_cart
    @gAdminDisplay = is_staff && !session.has_key?(:admin_disabled)
    true
  end

  def allow_guest_checkout?
    # Only if option is enabled, and a self-purchase is in progress for an order that is OK for guest checkout
    !@gAdminDisplay               &&
      @gOrderInProgress        &&
      @gOrderInProgress.ok_for_guest_checkout? &&
      Option.allow_guest_checkout
  end

  def reset_shopping           # called as a filter
    session.delete(:promo_code)
    @gOrderInProgress.destroy if @gOrderInProgress
    @gOrderInProgress = nil
    set_order_in_progress(nil)
    session.delete(:return_to)
    true
  end

  # a generic filter that can be used by any RESTful controller that checks
  # there's at least one instance of the model in the DB

  def has_at_least_one
    contr = self.controller_name
    klass = Kernel.const_get(contr.singularize.camelize)
    unless klass.count > 0
      flash[:alert] = "You have not set up any #{contr} yet."
      redirect_to :action => 'new'
    end
  end

  def set_order_in_progress(order)
    if order
      session[:cart] = order.id
    else
      session.delete(:cart)
    end
  end

  # Store the action to return to, or URI of the current request if no action given.
  # We can return to this location by calling #redirect_after_login.
  def return_after_login(route_params)
    session[:return_to] = route_params
  end

  def redirect_after_login(customer)
    redirect_to ((r = session.delete(:return_to)) ?
      r.merge(:customer_id => customer) :
      customer_path(customer))
  end

  def redirect_after_reset_token(customer)
    redirect_to ((r = session.delete(:return_to)) ?
      r.merge(:customer_id => customer) :
      change_password_for_customer_path(customer))
    flash[:alert] = I18n.t('login.change_password_now')
  end

  def find_cart
    # if there is an existing order that HAS NOT BEEN finalized, return it....
    if (o = Order.find_by(:id => session[:cart]))  &&  o.sold_on.nil?
      return o
    else                        # nuke it
      session.delete(:cart)
      nil
    end
  end

  # setup session etc. for an "external" login, eg by a daemon
  def login_from_external(c)
    session[:cid] = c.id
  end

  # filter that requires user to login before accessing account

  def is_logged_in
    redirect_to login_path unless logged_in?
  end

  def temporarily_unavailable
    flash[:alert] = "Sorry, this function is temporarily unavailable."
    redirect_to :back
  end

  %w(staff walkup boxoffice boxoffice_manager admin).each do |r|
    define_method "is_#{r}" do
      !session[:admin_disabled] && current_user && current_user.send("is_#{r}")
    end
    define_method "is_#{r}_filter" do
      redirect_to(login_path, :alert => "You must have at least #{ActiveSupport::Inflector.humanize(r)} privilege for this action.") unless
        !session[:admin_disabled] && current_user && current_user.send("is_#{r}")
    end
  end

  def download_to_excel(output,filename="data",timestamp=true)
    (filename << "_" << Time.current.strftime("%Y_%m_%d")) if timestamp
    send_data(output,:type => (request.user_agent =~ /windows/i ?
                               'application/vnd.ms-excel' : 'text/csv'),
              :filename => "#{filename}.csv")
  end

  def email_confirmation(method,*args)
    flash[:notice] ||= ""
    customer = args.first
    addr = customer.email
    if customer.valid_email_address?
      begin
        m = Mailer.send(method, *args).deliver_now
        flash[:notice] << I18n.translate('email.success', :addr => addr)
        Rails.logger.info("Confirmation email sent to #{addr}")
      rescue Net::SMTPError => e
        flash[:notice] << I18n.translate('email.error', :addr => addr, :message => e.message)
        Rails.logger.error("Emailing #{addr}: #{e.message} \n #{e.backtrace}")
      end
    else
      flash[:notice] << I18n.translate('email.not_attempted')
    end
  end

  def create_session(u = nil, action = '')
    logout_keeping_session!
    @user = u || yield(params)
    if @user && @user.errors.empty?
      # Protects against session fixation attacks, causes request forgery
      # protection if user resubmits an earlier form using back
      # button. Uncomment if you understand the tradeoffs.
      # reset_session
      self.current_user = @user
      session[:guest_checkout] = false
      # 'remember me' checked?
      new_cookie_flag = (params[:remember_me] == "1")
      handle_remember_cookie! new_cookie_flag
      # finally: reset all store-related session state UNLESS the login
      # was performed as part of a checkout flow
      reset_shopping unless @gOrderInProgress
      session[:new_session] = true
      if action == 'reset_token'
        return redirect_after_reset_token(@user)
      end
      redirect_after_login(@user)
    end
  end

  protected

  def new_session?
    # returns true the FIRST time it's called on a session.  Used for
    # displaying login-time messages, etc.
    session.delete(:new_session)
  end

end
