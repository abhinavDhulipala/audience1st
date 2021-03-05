require 'uri'
require File.expand_path(File.join(File.dirname(__FILE__), "..", "support", "paths"))
require "selenium-webdriver"
#require 'selenium/server'

Then /^I should see a JS alert$/ do
  driver = Selenium::WebDriver.for(:remote, :url => "https://google.com")
  #driver.is_alert_present.should be_true
  begin
    driver.switch_to.alert.accept
  rescue
    Selenium::WebDriver::Error::NoAlertOpenError
  end
end

Then /^I should see a "([^\"]*)" JS confirm dialog$/ do |string|
  selenium.get_alert.should eql(string)
end