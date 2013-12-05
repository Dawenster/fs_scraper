class Flight < ActiveRecord::Base
  belongs_to  :departure_airport,
              :class_name => Airport,
              :foreign_key => 'departure_airport_id'

  belongs_to  :arrival_airport,
              :class_name => Airport,
              :foreign_key => 'arrival_airport_id'

  def non_stop?
    number_of_stops == 0
  end

  def rounded_price
    (price / 100).round(0)
  end
end
