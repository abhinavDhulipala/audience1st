# to do:
#  add logic to init new donation with correct default account_code (from options)


class Donation < Item

  def self.default_code
    if (code = Option.value(:default_donation_account_code)).blank?
      AccountCode.default_account_code
    else
      AccountCode.find_by_code(code) ||
        AccountCode.create_by_code(code, "Default donation account") ||
        AccountCode.default_account_code
    end
  end
  
  belongs_to :account_code
  validates_associated :account_code
  validates_presence_of :account_code_id
  

  validates_numericality_of :amount
  validates_presence_of :sold_on
  validates_inclusion_of :amount, :in => 1..10_000_000, :message => "must be at least 1 dollar"

  def self.foreign_keys_to_customer
    [:customer_id, :processed_by_id]
  end

  def self.from_amount_and_account_code(amount, code)
    if code.blank? || (use_code = AccountCode.find_by_code(code)).nil?
      use_code = Donation.default_code
    end
    Donation.new(:amount => amount, :account_code => use_code)
  end

  def price ; self.amount ; end # why can't I use alias for this?

  def one_line_description
    sprintf("$%6.2f  Donation to #{account_code.name} (confirmation \##{id})", amount)
  end


  def self.walkup_donation(amount,logged_in_id,purch=Purchasemethod.get_type_by_name('box_cash'))
    Donation.create(:sold_on => Date.today,
                    :amount => amount,
                    :customer_id => Customer.walkup_customer.id,
                    :account_code => self.default_code,
                    :purchasemethod_id => purch.id,
                    :letter_sent => false,
                    :processed_by_id => logged_in_id)
  end
end
