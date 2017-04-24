class Donation < ActiveRecord::Base
  after_create :send_thankyou_postcard

  private

  def send_thankyou_postcard
    DonationWorker.perform_async(self.id)
  end
end
