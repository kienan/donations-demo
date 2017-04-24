class DonationsController < ApplicationController

  def new
  end

  def create
    @amount = (Float(params[:amount]) * 100).to_i # Must be an integer!

    begin
      charge = Stripe::Charge.create(
        :amount => @amount,
        :currency => 'usd',
        :source => params[:stripeToken],
        :description => 'Custom donation'
      )
    rescue Stripe::CardError => e
      flash[:error] = e.message
      redirect_to new_donation_path
    end

    donation = Donation.create(amount: params[:amount],
                               name: params[:shippingName],
                               stripe_token: params[:stripeToken],
                               address_line1: params[:shippingAddressLine1],
                               address_city: params[:shippingAddressCity],
                               address_state: params[:shippingAddressState],
                               address_country: params[:shippingAddressCountry],
                               address_zip: params[:shippingAddressZip])

    donation.save
  end
  
end
