require 'digest'

class MailchimpMailer
  def initialize(key = nil)
    @apikey = key || (Option.mailchimp_key rescue nil)
    @disabled = !!@apikey.blank?
    @errors = []
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
      @errors << e
      p Rails.logger.info "mailchimp init: #{@errors}"
    end
  end 

  #
  def get_list_id(email)
    begin
      # ref: https://github.com/mailchimp/mailchimp-marketing-ruby/blob/master/lib/MailchimpMarketing/api/lists_api.rb#L181
      response = @mailchimp.lists.get_all_lists({
                   email: email
                 })
      return 'response has no key', true unless response.key? "lists"
      lists = response["lists"]
      return response["lists"][0]["id"], false unless lists.empty?
      e = 'user not in list'
      @errors << e
      return e, true
    rescue MailchimpMarketing::ApiError => e
      @errors << e
      return e, true
    end
  end

  # batch add/remove list members to static segment
  # def batch_add()
  #   begin
  #     response = client.lists.batch_segment_members({}, 'list_id', 'segment_id')
  #     puts response
  #   rescue MailchimpMarketing::ApiError => e
  #     @errors << e
  #     return e.to_s, true
  #   end
  # end

  def create_segment(list_id, segment_name, emails_to_add)
    begin
      # 'name' and 'static segment' are required body params
      # which is an array of emails to be used for a static segment
      # an empty array will create a static segment without any members
      response = @mailchimp.lists.create_segment(list_id, { 'name' => segment_name, 'static_segment' => emails_to_add })
      return response
    rescue MailchimpMarketing::ApiError => e
      @errors << e
      return e.to_s, true
    end
  end

  # https://github.com/mailchimp/mailchimp-marketing-ruby/blob/master/lib/MailchimpMarketing/api/lists_api.rb#L1088
  # For now this method just gets the first segment in the list. Here as a template for future devs
  # @returns str(segment_id or error), bool(whether error was encountered)
  def find_segment(list_id)
    begin
      # further body params found here:  https://mailchimp.com/developer/marketing/api/list-segments/list-segments/
      response = @mailchimp.lists.list_segments(list_id, {
        exclude_fields: ['_links'],
        count: 1, # should be removed if we want to scan and filter segments more smartly; defaults to 10
      })

      segments = response['segments']
      return 'no segments available', true if segments.nil? or segments.empty?
      return segments[0]['id'], false
    rescue MailchimpMarketing::ApiError => e
      @errors << e
      return e.to_s, true
    end
  end

  private

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
