require 'rails_helper'

describe MailchimpMailer do
  before :each do
    @mail_list = MailchimpMailer.new
  end

  describe 'mailchimp API testing' do
    it 'pings a correct API response for the first call' do
      VCR.use_cassette('mailchimp_first_call') do
        t = EmailList.new
        response = t.mailchimp_init('ffffffffffffffffffffffffffffffff-us1')
        expect(response).to eq({
         "health_status" => "Everything's Chimpy!"
        })
      end
    end

  	it 'creates an event' do
  	  VCR.use_cassette('create_event') do
  	    @mail_list.mailchimp_init('ffffffffffffffffffffffffffffffff-us1')
        response = @mail_list.create_event('deadbeef', 'fake@gmail.com')
        expect(response).to eq(nil)
      end
    end
end