require 'rest_client'

task :scrape => :environment do
  start_time = Time.now
  flight_count = 0
  origin_code = ENV['CURRENT_AIRPORT']

  local = false

  puts "*" * 50
  puts "Commencing scraping sequence..."
  puts "Marking all old flights..."

  Flight.all.each { |flight| flight.update_attributes(:new => false) }
  if local
    route_results = JSON.parse(RestClient.get "http://localhost:3001/mark-flights-as-old", params: { :password => ENV['POST_PASSWORD'] })
    route_results = JSON.parse(RestClient.get "http://localhost:3000/routes-to-scrape", params: { :code => origin_code, :password => ENV['POST_PASSWORD'] })
  else
    route_results = JSON.parse(RestClient.get "http://fs-#{origin_code.downcase}-api.herokuapp.com/mark-flights-as-old", params: { :password => ENV['POST_PASSWORD'] })
    route_results = JSON.parse(RestClient.get "http://www.flyshortcut.com/routes-to-scrape", params: { :code => origin_code, :password => ENV['POST_PASSWORD'] })
  end

  date_array = []

  num_days = (1..75).to_a
  # num_days = [3, 5]

  num_days.each do |num|
    date_array << (Time.now + num.days).strftime('%m/%d/%Y')
  end

  puts "*" * 50
  puts "Scraping flights originating from #{origin_code}"

  date_array.each do |date|
    non_stop_flights = []
    potential_shortcuts = []

    Flight.where(:origin_code => origin_code, :pure_date => date).destroy_all

    route_results["routes"].each do |route_pair|
      begin
        origin = route_pair[0]
        origin_airport_id = Airport.find_by_code(origin).id
        destination = route_pair[1]
        destination_airport_id = Airport.find_by_code(destination).id
        formatted_date = date.split("/").rotate(2).join("-")
        cheapest_price = nil

        puts "*" * 50
        puts "#{origin}-#{destination}-#{date}"
        puts "*" * 50

        result_form = Nokogiri::HTML(RestClient.get "http://www.travelocity.com/Flights-Search?trip=oneway&leg1=from:#{origin},to:#{destination},departure:#{date}TANYT&passengers=children:0,adults:1,seniors:0,infantinlap:Y&mode=search")
        url = result_form.css("#flightResultForm")[0]["action"]
        url.gsub!("/Flights-Search-RoundTrip?", "")
        search_result = JSON.parse(RestClient.get "http://www.travelocity.com/Flight-Search-Outbound?" + url)

        itins = search_result["searchResultsModel"]["offers"]

        itins.each do |itin|
          begin
            segment = itin["legs"].first["timeline"].first
            formatted_departure_time = segment["departureTime"]["time"] + "m"
            formatted_arrival_time = segment["arrivalTime"]["time"] + "m"

            if itin["legs"].first["stops"] == 0
              created_flight = Flight.create! do |fl|
                fl.departure_airport_id = origin_airport_id
                fl.arrival_airport_id = destination_airport_id
                fl.departure_time = DateTime.strptime(formatted_date + '-' + formatted_departure_time, '%Y-%m-%d-%I:%M%p')
                fl.arrival_time = DateTime.strptime(formatted_date + '-' + formatted_arrival_time, '%Y-%m-%d-%I:%M%p')
                fl.arrival_time = fl.arrival_time + 1.day if fl.arrival_time < fl.departure_time
                fl.airline = segment["carrier"]["airlineName"]
                fl.flight_no = segment["carrier"]["flightNumber"]
                fl.price = (itin["legs"].first["price"]["totalPriceAsDecimal"] * 100).to_i
                fl.number_of_stops = 0
                fl.is_first_flight = true
                fl.pure_date = date
              end

              if created_flight.price == 0
                puts "Zero price!"
                raise "Price is 0"
              else
                non_stop_flights << created_flight
                cheapest_price = created_flight.price if (cheapest_price == nil || created_flight.price < cheapest_price)

                puts "Scraped Non-stop #{segment["carrier"]["airlineName"]} #{segment["carrier"]["flightNumber"]}"
                flight_count += 1
              end
            elsif itin["legs"].first["stops"] == 1
              flight = Flight.create! do |fl|
                fl.departure_airport_id = origin_airport_id
                fl.arrival_airport_id = Airport.find_by_code(segment["arrivalAirport"]["code"]).id
                fl.departure_time = DateTime.strptime(formatted_date + '-' + formatted_departure_time, '%Y-%m-%d-%I:%M%p')
                fl.arrival_time = DateTime.strptime(formatted_date + '-' + formatted_arrival_time, '%Y-%m-%d-%I:%M%p')
                fl.arrival_time = fl.arrival_time + 1.day if fl.arrival_time < fl.departure_time
                fl.airline = segment["carrier"]["airlineName"]
                fl.flight_no = segment["carrier"]["flightNumber"]
                fl.price = (itin["legs"].first["price"]["totalPriceAsDecimal"] * 100).to_i
                fl.number_of_stops = 1
                fl.is_first_flight = true
                fl.pure_date = date

                fl.second_flight_destination = destination_airport_id
                # fl.second_flight_no = itin['header'][1]['flightNumber']
              end

              if flight.price == 0
                puts "Zero price!"
                raise "Price is 0"
              else
                potential_shortcuts << flight
                cheapest_price = flight.price if (cheapest_price == nil || flight.price < cheapest_price)

                puts "Scraped One-stop #{segment["carrier"]["airlineName"]} #{segment["carrier"]["flightNumber"]}"
                flight_count += 1
              end
            end
          rescue
            created_flight.destroy if created_flight
            flight.destroy if flight
          end
        end
        Route.create! do |route|
          route.origin_airport_id = origin_airport_id
          route.destination_airport_id = destination_airport_id
          route.cheapest_price = cheapest_price
          route.date = date
        end
      rescue
      end
    end

    shortcuts = []
    almost_shortcuts = []
    non_shortcuts = []

    puts "*" * 50
    puts "Commencing shortcut calculations..."

    all_flights = non_stop_flights + potential_shortcuts

    potential_shortcuts.each do |flight|
      similar_flights = all_flights.select { |all_flight| all_flight.flight_no == flight.flight_no && all_flight.airline == flight.airline && all_flight.pure_date == flight.pure_date }
      similar_flights = similar_flights.sort_by { |flight| flight.price }

      cheapest_flight = similar_flights.first
      non_stop_flight = similar_flights.find {|f| f.number_of_stops == 0 }

      if non_stop_flight && cheapest_flight.price < (non_stop_flight.price - 2000) && !cheapest_flight.non_stop?
        cheapest_flight.update_attributes(:original_price => non_stop_flight.price, :origin_code => origin_code, :shortcut => true)
        shortcuts << cheapest_flight
        almost_shortcuts << flight unless flight == cheapest_flight
      else
        non_shortcuts << flight
      end
    end

    if shortcuts.any?
      puts "Deleting non-shortcut flights..."
      non_stop_flights.map { |flight| flight.destroy }
      non_shortcuts.map { |flight| flight.destroy }
      almost_shortcuts.map { |flight| flight.destroy }

      puts "Calculating epic wins..."

      shortcuts.uniq! { |flight| flight.flight_no + flight.airline + flight.pure_date }
      shortcuts.each do |flight|
        route = Route.where(:origin_airport_id => flight.departure_airport_id, :destination_airport_id => flight.arrival_airport_id, :date => flight.pure_date)[0]
        if (route.cheapest_price - flight.price) > 2000
          flight.update_attributes(:cheapest_price => route.cheapest_price, :new => true, :epic => true)
        else
          flight.update_attributes(:cheapest_price => route.cheapest_price, :new => true)
        end
      end

      # Send shortcut flights to API
      params = {
        :password => ENV['POST_PASSWORD'],
        :date => date,
        :flights => flights_to_json(shortcuts)
      }

      if local
        RestClient.post "http://localhost:3001/flights", params
      else
        RestClient.post "http://fs-#{origin_code.downcase}-api.herokuapp.com/flights", params
      end

      puts "#{origin_code} #{date} complete."
    else
      puts "No shortcuts found - deleting all flights on this itinerary..."
      all_flights.map { |flight| flight.destroy }
    end
  end

  puts "*" * 50
  puts "Destroying all routes..."

  Route.destroy_all

  puts "*" * 50
  puts "Destroying remaining old flights..."

  Flight.where(:new => false).destroy_all
  if local
    route_results = JSON.parse(RestClient.get "http://localhost:3001/delete-old-flights", params: { :password => ENV['POST_PASSWORD'] })
  else
    route_results = JSON.parse(RestClient.get "http://fs-#{origin_code.downcase}-api.herokuapp.com/delete-old-flights", params: { :password => ENV['POST_PASSWORD'] })
  end

  time = (Time.now - start_time).to_i
  puts "*" * 50
  puts "Total time: #{time / 60} minutes, #{time % 60} seconds"
  puts "Flights: #{flight_count}"
  puts "Shortcuts: #{Flight.count}"
  puts "Flights scraped per second: #{(flight_count / (Time.now - start_time)).round(2)}"
end

def flights_to_json(flights)
  json_flights = []
  flights.each_with_index do |flight, i|
    json_flights << { i => flight.as_json }
  end
  return json_flights
end