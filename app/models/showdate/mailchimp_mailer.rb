require 'digest'


class MailchimpMailer
  def initialize key=nil
    @apikey = key or Option.mailchimp_key rescue nil
    @disabled = !!@apikey.blank?
    @errors = []
    @mailchimp = nil
    mailchimp_init
  end


  # add an event for a list member
  # want to create an event for a contact when they confirm to attend a show
  # use the event to setup segments in our mailchimp audience
  # then we can add contacts to that segment
  # @returns a response object of the mailchimp call or a list of errors
  def create_event(id, user_email)
    begin
      list_id = id
      subscriber_hash = get_attendee_hash(user_email)

      # random
      options = {
        name: Segments, # We need to get the name from either a segment or a Relation with Showadte's corresponding customer
        properties: {
          show_date: Showdate.find().thedate
        }
      }

      @mailchimp.lists.create_list_member_event(
        list_id,
        subscriber_hash,
        options
      )
    rescue MailchimpMarketing::ApiError => e
      @errors << e
    end
  end

  def get_attendee_hash(email)
    Digest::MD5.hexdigest(email.downcase)
  end

  def create_segment(id)
    @mailchimp.lists.create_segment(
      list_id
    )

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

  def mailchimp_init
    begin
      @mailchimp = MailchimpMarketing::Client.new
      @mailchimp.set_config({
                              :api_key => @key,
                              :server => "us1"
                            })
      @mailchimp.ping.get
    rescue MailchimpMarketing::ApiError => e
      @errors << e
    end
  end
end