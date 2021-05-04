require 'digest'

class MailchimpMailer

  attr_reader :errors

  def initialize(key = nil)
    @apikey = key || (Option.mailchimp_key rescue nil)
    @disabled = !!@apikey.blank?
    @errors = []
  end

  def mailchimp_init(key)
    mailchimp_handler do
      @mailchimp = MailchimpMarketing::Client.new
      @mailchimp.set_config({
                              api_key: key,
                              server: "us1"
                            })
      @mailchimp.ping.get
      end
  end 

  # @returns the first list for a given user or nil if an error was encountered
  def get_list_id(email)
    mailchimp_handler do
      # ref: https://github.com/mailchimp/mailchimp-marketing-ruby/blob/master/lib/MailchimpMarketing/api/lists_api.rb#L181
      response = @mailchimp.lists.get_all_lists({
                   email: email
                 })
      if response.key? "lists"
        lists = response["lists"]
        response["lists"][0]["id"] unless lists.empty?
      end
    end
  end

  def create_segment(list_id, segment_name, emails_to_add)
    mailchimp_handler do
      # 'name' and 'static segment' are required body params
      # which is an array of emails to be used for a static segment
      # an empty array will create a static segment without any members
      @mailchimp.lists.create_segment(list_id, { 'name' => segment_name, 'static_segment' => emails_to_add })
      end
  end

  # https://github.com/mailchimp/mailchimp-marketing-ruby/blob/master/lib/MailchimpMarketing/api/lists_api.rb#L1088
  # For now this method just gets the first segment in the list. Here as a template for future devs
  # @returns str(segment_id or nil)
  def find_segment(list_id)
    mailchimp_handler do
      # further body params found here:  https://mailchimp.com/developer/marketing/api/list-segments/list-segments/
      response = @mailchimp.lists.list_segments(list_id, {
        exclude_fields: ['_links'],
        count: 1, # should be removed if we want to scan and filter segments more smartly; defaults to 10
      })

      segments = response['segments']
      unless segments.nil? or segments.empty?
        segments[0]['id']
      end
    end

  end

  private

  def mailchimp_handler &block
    begin
      block.call
    rescue MailchimpMarketing::ApiError => e
      @errors << e
      Rails.logger.info "mailchimp error: #{e}"
      nil
    end
  end


  def mailchimp_body_for(customer)
    {
      email_address: customer.email,
      status: customer.e_blacklist ? 'unsubscribed' : 'subscribed',
      merge_fields: {'FNAME' => customer.first_name, 'LNAME' => customer.last_name}
    }
  end

  def customer_id_from(email)
    Digest::MD5.hexdigest(email.downcase)
  end
end
