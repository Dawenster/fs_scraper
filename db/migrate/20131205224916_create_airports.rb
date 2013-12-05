class CreateAirports < ActiveRecord::Migration
  def change
    create_table :airports do |t|
      t.string :code
      t.string :name
      t.string :city
      t.float :latitude
      t.float :longitude
      t.string :timezone
    end
  end
end
