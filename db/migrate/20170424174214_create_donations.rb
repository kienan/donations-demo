class CreateDonations < ActiveRecord::Migration
  def change
    create_table :donations do |t|
      t.integer :amount
      t.string :stripe_token
      t.string :name
      t.string :address_line1
      t.string :address_city
      t.string :address_state
      t.string :address_zip
      t.string :address_country

      t.timestamps
    end
  end
end
