require 'digest'


class MailchimpMailer
  def initialize(key = nil)
    @apikey = key || (Option.mailchimp_key rescue nil)
    @disabled = !! @apikey.blank?
    @errors = []
    @mailchimp = nil
  end

  def mailchimp_init(key)
    begin
      @mailchimp = MailchimpMarketing::Client.new
      @mailchimp.set_config({
                              :api_key => key,
                              :server => "us1"
                            })
      response = @mailchimp.ping.get
      response
    rescue MailchimpMarketing::ApiError => e
      puts "Error: #{e}"
      @errors << e
      Rails.logger.info "mailchimp init: #{@errors}"
    end
  end

  # add an event for a list member
  # want to create an event for a contact when they confirm to attend a show
  # use the event to setup segments in our mailchimp audience
  # then we can add contacts to that segment
  # @returns a response object of the mailchimp call or a list of errors
  #
  def create_event(id, user_email)
    begin
      list_id = id
      subscriber_hash = get_attendee_hash(user_email)

      # random
      options = {
        name: "confirmed_attendee",
        properties: {
          show_date: "4-16-2021"
        }
      }
      # retirve list id,
      # hash email who u want to add to create member event
      #

      response = @mailchimp.lists.create_list_member_event(
        list_id,
        subscriber_hash,
        options
      )
      response
    rescue MailchimpMarketing::ApiError => e
      puts "Error: #{e}"
    end
  end

  def get_attendee_hash(email)
    Digest::MD5.hexdigest(email.downcase)
  end

  def create_segment(id, show_name, show_date)
    list_id = id
    @mailchimp.lists.create_segment(
      list_id: list_id,
      name: "#{show_name}_#{show_date}",
      options: options
    )

  end

  # don't do this
  # batch add/remove list members to static segment
  def batch_add()
    begin
      response = client.lists.batch_segment_members({}, 'list_id', 'segment_id')
      puts response
    rescue MailchimpMarketing::ApiError => e
      puts "Error: #{e}"
    end
  end

  private

  def mailchimp_body_for customer
    {
      email_address: customer.email,
      status: customer.e_blacklist ? 'unsubscribed' : 'subscribed',
      merge_fields: {'FNAME' => customer.first_name, 'LNAME' => customer.last_name}
    }
  end

  def customer_id_from email
    Digest::MD5.hexdigest(email.downcase)
  end


end