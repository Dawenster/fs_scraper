class Airport < ActiveRecord::Base
  has_one :flight, 
          :class_name => Flight, 
          :foreign_key => 'departure_city_id'

  has_one :flight, 
          :class_name => Flight, 
          :foreign_key => 'arrival_city_id'
end
