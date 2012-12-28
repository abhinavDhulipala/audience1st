class StoreController < ApplicationController

  skip_before_filter :verify_authenticity_token, :only => %w(show_changed showdate_changed comment_changed redeeming_promo_code)

  before_filter :is_logged_in, :only => %w[edit_billing_address]
  before_filter :is_admin_filter, :only => %w[direct_transaction]

  before_filter :set_session_variables
  def set_session_variables
    @customer = current_user || Customer.walkup_customer
    @cart = find_cart
    @promo_code = session[:promo_code]
    @is_admin = current_admin.is_boxoffice
  end
  private :set_session_variables
  
  verify(:method => :post,
         :only => %w[process_cart set_shipping_address place_order],
         :add_to_flash => {:warning => "SYSTEM ERROR: action only callable as POST"},
         :redirect_to => {:action => 'index'})

  # this should be the last declarative spec since it will append another
  # before_filter
  ssl_required(:checkout, :place_order, :direct_transaction,
                 :index, :subscribe, :special, :donate,
                 :show_changed, :showdate_changed,
                 :shipping_address, :set_shipping_address,
                 :comment_changed,
                 :edit_billing_address)

  
  def index
    unless (@promo_code = redeeming_promo_code)
      reset_shopping
      setup_for_showdate(showdate_from_params || showdate_from_show_params || showdate_from_default)
    end
    @subscriber = @customer.subscriber?
    @next_season_subscriber = @customer.next_season_subscriber?
    set_return_to :action => self.action_name
  end

  def special
    @special_shows_only = true
    render :action => :index
  end

  def subscribe
    reset_shopping
    set_return_to :controller => 'store', :action => 'subscribe'
    @subscriber = @customer.subscriber?
    @next_season_subscriber = @customer.next_season_subscriber?
    @cart = find_cart
    # this uses the temporary hack of adding bundle sales start/end
    #   to bundle voucher record directly...ugh
    @promo_code = redeeming_promo_code
    @subs_to_offer =
      Vouchertype.bundles_available_to(@customer, @gAdmin.is_boxoffice).using_promo_code(@promo_code)
    if @subs_to_offer.empty?
      flash[:warning] = "There are no subscriptions on sale at this time."
      redirect_to_index
      return
    end
    if (v = params[:vouchertype_id]).to_i > 0 && # default selected subscription
        vt = Vouchertype.find_by_id(v) &&
        # note! must use grep (uses ===) rather than include (uses ==)
        @subs_to_offer.grep(vt)
      @selected_sub = v.to_i
    end
  end

  def donate
    @account_code = AccountCode.find_by_id(params[:fund]) ||
      AccountCode.default_account_code
  end

  def process_cart
    if params[:commit] =~ /redeem/i # customer entered promo code, redisplay prices
      redirect_to(stored_action.merge({:commit => 'redeem', :promo_code => params[:promo_code]}))
      return
    end
    @cart = find_cart
    @cart.purchaser = @customer
    @cart.comments = params[:comments]
    @cart.processed_by_id = logged_in_id
    process_ticket_request
    redirect_to_index and return if flash[:warning]
    # all well with cart, try to process donation if any
    if params[:donation].to_i > 0
      @cart.add_donation( Donation.from_amount_and_account_code(params[:donation].to_i,
          params[:account_code_id] ))
    end
    remember_cart_in_session!
    if params[:gift] && @cart.include_vouchers?
      redirect_to :action => 'shipping_address'
    else
      @cart.customer = @cart.purchaser
      redirect_to_checkout
    end
  end

  def shipping_address
    #  collect gift recipient info
    @cart = find_cart
    set_checkout_in_progress true
    @recipient = @cart.customer || Customer.new
  end

  def set_shipping_address
    @cart = find_cart
    # if we can find a unique match for the customer AND our existing DB record
    #  has enough contact info, great.  OR, if the new record was already created but
    #  the buyer needs to modify it, great.
    #  Otherwise... create a NEW record based
    #  on the gift receipient information provided.
    recipient = recipient_from_session || recipient_from_params ||
      Customer.new(params[:customer])
    # make sure minimal info for gift receipient was specified.
    recipient.gift_recipient_only = true
    if recipient.new_record?
      recipient.created_by_admin = true if current_admin.is_boxoffice
      unless recipient.save
        flash[:warning] = recipient.errors.full_messages
        render :action => :shipping_address
        return
      end
    end
    @cart.customer = recipient
    redirect_to_checkout
  end

  def checkout
    set_return_to :controller => 'store', :action => 'checkout'
    @cart = find_cart
    # Work around Rails bug 2298 here
    @sales_final_acknowledged = (params[:sales_final].to_i > 0) || current_admin.is_boxoffice
    @checkout_message = Option.value(:precheckout_popup) ||
      "PLEASE DOUBLE CHECK DATES before submitting your order.  If they're not correct, you will be able to Cancel before placing the order."
    # if this is a "walkup web" sale (not logged in), nil out the
    # customer to avoid modifing the Walkup customer.
    redirect_to change_user_path and return unless logged_in?
  end

  def edit_billing_address
    set_return_to :controller => 'store', :action => 'checkout'
    flash[:notice] = "Please update your credit card billing address below. Click 'Save Changes' when done to continue with your order."
    redirect_to :controller => 'customers', :action => 'edit'
  end

  def place_order
    @cart = find_cart
    @is_admin = current_admin.is_boxoffice
    # what payment type?
    @cart.purchasemethod,@cart.purchase_args = purchasemethod_from_params
    unless @cart.ready_for_purchase?
      flash[:warning] = @cart.errors.full_messages.join(', ')
      redirect_to_checkout
      return
    end
    @recipient = @cart.purchaser
    redirect_to_checkout and return unless verify_sales_final
    if ! @cart.gift?
      # record 'who will pickup' field if necessary
      @cart.comments << "(Pickup by: #{ActionController::Base.helpers.sanitize(params[:pickup])})" unless params[:pickup].blank?
    end

    begin
      @cart.finalize!
      logger.info("SUCCESS purchase #{@cart.customer}; Cart summary: #{@cart.summary}")
      email_confirmation(:confirm_order, @cart) if params[:email_confirmation]
      reset_shopping
      set_return_to
    rescue Order::PaymentFailedError, Order::SaveRecipientError, Order::SavePurchaserError
      flash[:checkout_error] = @cart.errors.full_messages.join(', ')
      logger.info("FAILED purchase for #{@cart.customer}: #{@cart.errors.inspect}") rescue nil
      redirect_to_checkout
    rescue Exception => e
      flash[:checkout_error] = "Sorry, an unexpected problem occurred with your order.  Please try your order again."
      logger.error("Unexpected exception: #{e.message}")
      redirect_to_index
    end

  end

  # helpers for the AJAX handlers. These should probably be moved
  # to the respective models for shows and showdates, or called as
  # helpers from the views directly.

  def show_changed
    setup_for_showdate(showdate_from_show_params || showdate_from_default)
    render :partial => 'ticket_menus'
  end

  def showdate_changed
    setup_for_showdate(showdate_from_params || showdate_from_default)
    render :partial => 'ticket_menus'
  end

  def comment_changed
    cart = find_cart
    cart.comments = params[:comments]
    render :nothing => true
  end

  private

  def redeeming_promo_code
    case params[:commit]
    when /clear/i
      session.delete(:promo_code)
      logger.info("Clearing promo code")
      nil
    when /redeem/i
      params.delete(:commit)
      logger.info "Accepting promo code #{params[:promo_code]}"
      session[:promo_code] = params[:promo_code].to_s.upcase
    else
      nil
    end
  end

  def showdate_from_params
    Showdate.find_by_id(params[:showdate_id], :include => [:show, :valid_vouchers])
  end
  def showdate_from_show_params
    (s = Show.find_by_id(params[:show_id], :include => :showdates)) &&
      s.has_showdates &&
      s.showdates.first
  end
  def showdate_from_default ; Showdate.current_or_next ; end
  
  def process_ticket_request
    unless (showdate = Showdate.find_by_id(params[:showdate])) ||
        params[:donation].to_i > 0
      flash[:warning] = "Please select a show date and tickets, or enter a donation amount."
      return
    end
    params[:valid_voucher] ||= {}
    admin = @gAdmin.is_boxoffice
    # pre-check whether the total number of tickets exceeds availability
    total = params[:valid_voucher].values.sum
    if showdate && total > showdate.saleable_seats_left  &&  !admin
      flash[:warning] = "You've requested #{total} tickets, but only #{showdate.saleable_seats_left} are available for this performance."
    else
      params[:valid_voucher].each_pair do |valid_voucher_id, qty|
        @cart.add_tickets(valid_voucher_id, qty)
      end
    end
  end

  def recipient_from_session
    if ((s = session[:recipient_id]) &&
        (recipient = Customer.find_by_id(s)))
      recipient.update_attributes(params[:customer])
      recipient
    else
      nil
    end
  end

  def recipient_from_params
    recipient = Customer.find_unique(Customer.new(params[:customer]))
    recipient && recipient.valid_as_gift_recipient? ? recipient : nil
  end

  def remember_cart_in_session!
    @cart.save!
    session[:cart] = @cart.id
  end
  
  def verify_sales_final
    return true if Option.value(:terms_of_sale).blank? || !params[:sales_final].blank?
    flash[:checkout_error] = "Please indicate your acceptance of our Sales Final policy by checking the box."
    return nil
  end

  def redirect_to_checkout
    redirect_to(:action => 'checkout',
      :sales_final => params[:sales_final],
      :email_confirmation => params[:email_confirmation])
    true
  end

  def redirect_to_index
    url_or_path = params[:redirect_to]
    if url_or_path.empty?
      redirect_to :action => 'index'
    elsif url_or_path =~ /\//
      redirect_to url_or_path
    else
      redirect_to :action => url_or_path
    end
  end

  def purchasemethod_from_params
    if ( !@is_admin || params[:commit ] =~ /credit/i ) 
      meth = Purchasemethod.get_type_by_name(@cart.customer.id == logged_in_id ? 'web_cc' : 'box_cc')
      args = { :credit_card_token => params[:credit_card_token] }
    elsif params[:commit] =~ /check/i
      meth = Purchasemethod.get_type_by_name('box_chk')
      args = {:check_number => params[:check_number] }
    elsif params[:commit] =~ /cash/i
      meth = Purchasemethod.get_type_by_name('box_cash')
      args = {}
    else
      flash[:warning] = "Invalid form of payment."
      redirect_to_checkout
    end
    return meth,args
  end

  def setup_for_showdate(sd)
    @sd = sd
    @sh = @sd.show
    @special_shows_only = @sh.special?
    @all_showdates = @sh.showdates
    if @is_admin then setup_ticket_menus_for_admin else setup_ticket_menus_for_patron end
  end

  def setup_ticket_menus_for_admin
    @valid_vouchers = @sd.valid_vouchers
    @all_shows = Show.
      all_for_seasons(Time.this_season - 1, Time.this_season).
      find_by_special(@special_shows_only)  ||  []
    # ensure default show is included in list of shows
    @all_shows << @sh unless @all_shows.include? @sh
  end

  def setup_ticket_menus_for_patron
    @valid_vouchers = @sd.valid_vouchers.map do |v|
      v.adjust_for_customer(@customer,@promo_code)
    end.find_all(&:visible?)
    @all_shows = Show.current_and_future.find_by_special(@special_shows_only) || []
    @all_shows << @sh unless @all_shows.include? @sh
  end
end
