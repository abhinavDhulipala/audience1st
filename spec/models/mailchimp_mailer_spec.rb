require 'rails_helper'

# We used our own personal, live key to test these requests.
# VCR now stores those response and intercepts them on every test.
# If you are modifying the functionality of any given method in this test you should first delete the corresponding VCR
# found under /spec/fixtures/vcr_cassettes

describe MailchimpMailer do
  before do
    @mail_list = MailchimpMailer.new
    @list_id = 'de95a6457e'
    @segment_id = 1604350
    @api_key = 'insert your key here and delete VCR if you want to modify this test'
  end

  describe 'mailchimp API testing' do
    it 'pings a correct API response for the first call' do
      VCR.use_cassette('new_mailchimp_class') do
        response = @mail_list.mailchimp_init('your mailchimp key')
        expect(response).to eq({
         "health_status" => "Everything's Chimpy!"
        })
      end
    end

    it 'get list id' do
      VCR.use_cassette('mailchimp_list_id') do
      	  @mail_list.mailchimp_init(@api_key)
      	  response = @mail_list.get_list_id('kkhus5@berkeley.edu')
      	  expect(response).to eq(@list_id)
      end
    end

    it 'retrieves all segments in a list' do
      VCR.use_cassette('mailchimp_retrieve_segments') do
        @mail_list.mailchimp_init(@api_key)
        response = @mail_list.find_segment(@list_id)
        expect(response).to eq(@segment_id)
      end
    end

    it 'creates a segment' do
      VCR.use_cassette('mailchimp_create_segment') do
        @mail_list.mailchimp_init(@api_key)
        segment_name = 'Segment Name'
        emails_to_add = []
        response = @mail_list.create_segment(@list_id, segment_name, emails_to_add)
        expect(response['list_id']).to eq(@list_id)
        expect(response['name']).to eq('Segment Name')
        expect(response['member_count']).to eq(0)
      end
    end
  end
end
