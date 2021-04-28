require 'rspec'

describe MailchimpMailer do
  before :each do
    @mail_list = MailchimpMailer.new('ffffffffffffffffffffffffffffffff-us1')
    @known_emails = %w(af-theater@reinysfox.com af-www@reinysfox.com fox@a1patronsystems.com)
    @customers = @known_emails.map { |c| Customer.create! email: c }
  end

  describe 'segment manipulation' do


  end
end