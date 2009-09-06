# methods added to Time to speak the correct time, and a new contructor for
# making a Time from menus

# add a couple of useful formats to ActiveSupport to_formatted_s conversion
ActiveSupport::CoreExtensions::Time::Conversions::DATE_FORMATS.merge!({
  :date_only => "%e %B %Y",
  :showtime => '%A, %b %e, %l:%M %p',
  :month_day_only => "%b %e",
  :month_day_year => "%b %e, %Y"
})

class Time
  # Needed since DB may not be in same timezone, so its notion of NOW() may
  # not be correct
  def self.db_now
    "\"#{Time.now.to_formatted_s(:db)}\""
  end

  def speak(args={})
    res = []
    unless args[:omit_date]
      res << strftime("%A, %B %e")
    end
    unless args[:omit_time]
      say_min = min.zero? ? "" :  min < 10 ? "oh #{min}" : min
      res << "#{self.strftime('%I').to_i} #{say_min} #{self.strftime('%p')[0,1]} M"
    end
    res.join(", at ")
  end

  def at_end_of_day
    (self + 1.day).midnight - 1.second
  end

  def at_beginning_of_season(oldyear = self.year)
    oldyear = oldyear.to_i
    mon = Option.value(:season_start_month)
    mday = Option.value(:season_start_day)
    mon = 1 unless (1..12).include?(mon)
    mday = 1 unless (1..31).include?(mday)
    self.change(:month => mon, :day => mday, :hour => 0,
                :year => (self.yday >= Time.local(oldyear,mon,mday).yday ?
                          oldyear : oldyear - 1))
  end

  def at_end_of_season(oldyear = self.year)
    self.at_beginning_of_season(oldyear) + 1.year - 1.day
  end

  def within_season?(year)
    year = year.year unless year.kind_of?(Numeric)
    start = Time.local(year,Option.value(:season_start_month),
                       Option.value(:season_start_day)).at_beginning_of_season
    (start <= self) && (self <= start.at_end_of_season)
  end

  def self.from_param(param,default=Time.now)
    return default if param.blank?
    return Time.parse(param) unless param.kind_of?(Hash)
    if param.has_key?(:hour)
      Time.local(param[:year].to_i,param[:month].to_i,param[:day].to_i,param[:hour].to_i,
                 (param[:minute] || "00").to_i,
                 (param[:second] || "00").to_i)
    else
      Time.local(param[:year].to_i,param[:month].to_i,param[:day].to_i)
    end
  end

  def self.range_from_params(minp,maxp,default=Time.now)
    min = Time.from_param(minp)
    max = Time.from_param(maxp)
    min,max = max,min if min > max
    return min,max
  end

end

class Date
  def at_beginning_of_season(arg=self.year)
    self.to_time.at_beginning_of_season(arg).to_date
  end
  def at_end_of_season(arg=self.year)
    self.to_time.at_end_of_season(arg).to_date
  end
  def within_season?(arg)
    self.to_time.within_season?(arg)
  end
end
