class DonationWorker
  include Sidekiq::Worker

  def perform(donation_id)
    lob = Lob::Client.new(api_key: ENV['LOB_API_KEY'])
    donation = Donation.find(donation_id)

    # Dynamically get the correct template given the donation amount
    template_dict = {
      '10' => ENV['TEMPLATE_FRONT_10'],
      '20' => ENV['TEMPLATE_FRONT_20'],
      '50' => ENV['TEMPLATE_FRONT_50'],
    }

    front_template = template_dict[donation.amount.to_s]

    # Send the thank you postcard
    begin
      postcard = lob.postcards.create({
        description: "Thank You Postcard - #{donation.id}",
        to: {
          name: donation.name,
          address_line1: donation.address_line1,
          address_city: donation.address_city,
          address_state: donation.address_state,
          address_zip: donation.address_zip
        },
        front: front_template,
        back: ENV['TEMPLATE_BACK'],
        data: {
          name: donation.name,
          amount: donation.amount
        },
        metadata: {
          donation_id: donation.id
        }
      })
    rescue => e
      puts e
    end

  end
end
