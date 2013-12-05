# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20131205230545) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "airports", force: true do |t|
    t.string "code"
    t.string "name"
    t.string "city"
    t.float  "latitude"
    t.float  "longitude"
    t.string "timezone"
  end

  create_table "flights", force: true do |t|
    t.integer  "departure_airport_id"
    t.integer  "arrival_airport_id"
    t.datetime "departure_time"
    t.datetime "arrival_time"
    t.string   "airline"
    t.string   "flight_no"
    t.integer  "price"
    t.integer  "number_of_stops"
    t.boolean  "is_first_flight"
    t.integer  "second_flight_destination"
    t.integer  "second_flight_no"
    t.integer  "original_price"
    t.string   "origin_code"
    t.boolean  "shortcut"
    t.string   "pure_date"
    t.integer  "cheapest_price"
    t.boolean  "epic"
    t.string   "month"
    t.boolean  "new"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "routes", force: true do |t|
    t.integer "origin_airport_id"
    t.integer "destination_airport_id"
    t.integer "cheapest_price"
    t.string  "date"
  end

end
