class ValidVouchersController < ApplicationController

  def index
    list
    render :action => 'list'
  end

  # GETs should be safe (see http://www.w3.org/2001/tag/doc/whenToUseGet.html)
  verify :method => :post, :only => [ :create, :update ],
  :redirect_to => { :controller => :shows, :action => :list }

  def show
    @valid_voucher = ValidVoucher.find(params[:id])
    @showdate = @valid_voucher.showdate
  end

  def new
    @showdate_id = params[:showdate_id]
    @showdate = Showdate.find(@showdate_id)
    raise "New voucher type must be associated with a valid showdate" unless @showdate.kind_of?(Showdate)
    @valid_voucher = ValidVoucher.new
    # set some convenient defaults for new valid_voucher
    @valid_voucher.end_sales = @showdate.end_advance_sales
  end

  def create
    msgs = ''
    args = params[:valid_voucher]
    hours_before = (params[:end_is_relative].to_i > 0 ?
                    params[:hours_before].to_f.hours :
                    false)
    showdate = Showdate.find(args[:showdate_id])
    raise "New voucher type must be added to valid showdate" unless showdate.kind_of?(Showdate)
    addtojustone = params[:addtojustone].to_i
    if addtojustone.zero?
      # add voucher type to all dates
      showdate.show.showdates.each do |dt|
        args[:showdate_id] = dt.id
        vv = ValidVoucher.new(args)
        if hours_before
          vv.end_sales = dt.thedate - hours_before
        end
        vv.save!
      end
      if (msgs == '')
        msgs = 'Ticket type added to all dates'
      end
    else
      # add to just one date
      @validvoucher = ValidVoucher.new(params[:valid_voucher])
      if hours_before
        @validvoucher.end_sales = showdate.thedate - hours_before
      end
      if @validvoucher.save
        msgs = 'Added to date' + showdate.thedate.strftime('%b %e %y %I:%M%p') # ugh
      else
        msgs = error_messages_for :valid_voucher
      end
    end
    flash[:notice] = msgs
    redirect_to :controller => 'shows', :action => 'edit', :id => showdate.show.id

  end

  def edit
    @valid_voucher = ValidVoucher.find(params[:id])
    @showdate = @valid_voucher.showdate
  end

  def update
    @valid_voucher = ValidVoucher.find(params[:id])
    begin
      # this is ugly: we incur 2 database writes on an update if
      # end_is_relative  is set.
      @valid_voucher.update_attributes!(params[:valid_voucher])
      if params[:end_is_relative].to_i > 0
        @valid_voucher.update_attribute(:end_sales,
           @valid_voucher.showdate.thedate - params[:hours_before].to_f.hours)
      end
      flash[:notice] = 'Update successful'
    rescue Exception => e
      flash[:notice] = e.message + @valid_voucher.errors.full_messages.join("\n")
    end
    redirect_to :controller => 'shows', :action => 'edit', :id => @valid_voucher.showdate.show.id
  end

  def destroy
    v = ValidVoucher.find(params[:id])
    theShowID = v.showdate.show.id
    ValidVoucher.find(params[:id]).destroy
    redirect_to :controller => 'shows', :action => 'edit', :id => theShowID
  end

end
