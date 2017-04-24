# Using Lob Templates to Send Tailored Thank You Cards in Rails

Nonprofits and other organizations constantly struggle to increase their donations. Oftentimes this means improving the donation *process* by making it easier, faster, more transparent, or even more personal. With the tools available today, these sorts of improvements are easier than ever. In this post, we'll be covering one such way to improve the donation process.

> Just want to see the source code? We've got it all available in a [public repository].

## Overview

In this tutorial, we'll be building an app that attempts to improve the donation experience by sending personalized postcards upon receipt of donations. We'll be using Stripe to take donations and Lob to automatically send tailored "thank you" postcards. Instead of one, generic postcard design, we'll be using three that highlight the different impacts of each amount. 

### Prerequisites

In this guide, we'll be using the Ruby on Rails web framework as well as a range of APIs. Therefore, some familiarity with web development, Rails, and APIs is recommended, though don't worry if you're not an expert! 

### Key Tools

* **Ruby on Rails** – Rails is a popular web application framework running on the Ruby programming language. See [installrails.com](installrails.com) for an in-depth startup guide.
* **Redis** - Redis is a popular in-memory data store that we'll be using to handle our application's service workers. See the [official quickstart guide](https://redis.io/topics/quickstart) for more info.
* **Lob Postcard API and Templates** – Lob has a whole suite of [RESTful APIs for printing and mailing](https://lob.com/). We will be using the [Postcard API](https://lob.com/docs/ruby#postcards) in this tutorial. 
    * Be sure to [sign up for an account](https://dashboard.lob.com/#/register?utm_source=blog) if you haven't already!
* **Stripe API and Stripe Checkout** - Stripe provides a range of tools for [processing payments online](https://stripe.com/). In addition to its API, we'll be using [Checkout](https://stripe.com/checkout) to handle the payment frontend.
    * Sign up for an account [here](https://dashboard.stripe.com/register).

You'll need your API keys for Lob and Stripe handy, which can be found [here](https://dashboard.lob.com/#/settings/keys) and [here](https://dashboard.stripe.com/account/apikeys) respectively.

## Getting Started

### Generate Project
First, let's have Rails start up our project:
```sh
$ rails new donations-demo
$ cd donations-demo
```
### Install Dependencies
Add the following lines to the end of the `Gemfile`:
```ruby
# Gemfile

gem 'stripe', '~> 2.1.0' # Stripe's Ruby API wrapper
gem 'lob', '~> 3.0.0' # Lob's Ruby API wrapper
gem 'sidekiq', '~> 4.2.10' # Gem to handle service workers
gem 'figaro', '~> 1.1.0' # Gem to help us with configuration
```
Then, install the above dependencies:
```
$ bundle install
```

### Configure API keys
Next, we'll want to add our API keys into our project and initialize the Stripe wrapper. We'll use Figaro to automatically set up a `config/application.yml` file where we can securely store our API keys. Figaro automatically generates a `.gitignore` and adds the `application.yml` file. Run the following command:
```sh
$ bundle exec figaro install
```

Next, add in our API keys to `config/application.yml`
```yml
# config/application.yml

STRIPE_API_KEY: sk_test_xxxxxxxxxxxxxxxxxxxxxxxx
STRIPE_PUBLISHABLE_KEY: pk_test_xxxxxxxxxxxxxxxxxxxxxxxx
LOB_API_KEY: test_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Next, initialize the Stripe wrapper by creating the file `config/initializers/stripe.rb`:

```ruby
# config/initializers/stripe.rb

Rails.configuration.stripe = {
    :publishable_key => ENV['STRIPE_PUBLISHABLE_KEY'],
    :secret_key      => ENV['STRIPE_API_KEY']
}
Stripe.api_key = Rails.configuration.stripe[:secret_key]
```
With the above configuration all set, we can begin work on our app's functionality.

## Building our Application

### Set Up the Donation Model
We'll begin by creating a donation model to handle the details of each donation:

```sh
$ rails generate model Donation
```
Next, add in all the necessary fields to the migration Rails automatically generated for us. We'll want fields to track the Stripe charge as well as donor details such as name and address:

```ruby
# db/migrate/{timestamp}_create_donations.rb

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
```
Then run that migration:
```sh
$ rake db:migrate
```

Finally, add a `send_thankyou_postcard` method to the `Donation` model. We'll have Rails call this function whenever a donation is created. That way, for every donation we process, we'll automatically send out a thank you postcard. The function itself will call our `DonationWorker`, which we'll implement later on. 
```ruby
# app/models/donation.rb

class Donation < ActiveRecord::Base
  after_create :send_thankyou_postcard

  private

  def send_thankyou_postcard
    DonationWorker.perform_async(self.id)
  end
end
```
### Generate the Donation Controller and Modify Views
With our model set up, we'll next generate the necessary controller and views to handle donation creation:
```shell=bash
$ rails generate controller donations new create
```
This should've created the following files for us:
- `app/controllers/donations_controller.rb`
- `app/views/donations/create.html.erb`
- `app/views/donations/new.html.erb`

First, modify the `new` view, adding our donation form and Stripe Checkout: 
```html
<!-- app/views/donations/new.html.erb -->

<%= form_tag donations_path do %>
  <article>
    <%= label_tag(:amount, 'Donation Amount:') %>
    <%= select_tag "amount", options_for_select(["10", "20", "50"], "10") %>
  </article>
  <article>
    <%= hidden_field_tag(:stripeToken) %>
    <%= hidden_field_tag(:shippingName) %>
    <%= hidden_field_tag(:shippingAddressLine1) %>
    <%= hidden_field_tag(:shippingAddressZip) %>
    <%= hidden_field_tag(:shippingAddressCity) %>
    <%= hidden_field_tag(:shippingAddressState) %>
    <%= hidden_field_tag(:shippingAddressCountry) %>
  </article>
  <button id='donateButton'>Donate</button>
<% end %>
<script src="https://checkout.stripe.com/checkout.js"></script>
<script>
// This handler will set up Stripe Checkout and set the hidden values in our form declared above.
var handler = StripeCheckout.configure({
  key: '<%= ENV["STRIPE_PUBLISHABLE_KEY"] %>',
  locale: 'auto',
  name: 'Our Nonprofit',
  description: 'One-time donation',
  billingAddress: true,
  shippingAddress: true,
  token: function (token, args) {
    $('input#stripeToken').val(token.id);
    $('input#shippingName').val(args['shipping_name']);
    $('input#shippingAddressLine1').val(args['shipping_address_line1']);
    $('input#shippingAddressZip').val(args['shipping_address_zip']);
    $('input#shippingAddressCity').val(args['shipping_address_city']);
    $('input#shippingAddressState').val(args['shipping_address_state']);
    $('input#shippingAddressCountry').val(args['shipping_address_country']);
    $('form').submit();
  }
});

// Parse amount and open Checkout on donation button click
$('#donateButton').on('click', function(e) {
  e.preventDefault();

  var amount = $('select#amount').val();
  amount = parseFloat(amount) * 100; // Needs to be an integer!

  handler.open({
    amount: Math.round(amount)
  })
});

// Close Checkout on page navigation
$(window).on('popstate', function() {
  handler.close();
});
</script>
```

With this view, we'll have our simple donation form with Stripe Checkout functionality baked in.

[Screenshot of form and checkout side by side `donation_form.png`, `donation_stripe.png`]

Next, change the `create` view which will be displayed after a donation's been accepted:
```html
<!-- app/views/donations/create.html.erb -->

<h2>Thank you!</h2>
<p>Your donation of <strong><%= number_to_currency(@amount * 0.01) %></strong>
 has been received.</p>
```

Finally, edit `routes.rb` by replacing the automatically generated routes with the following line:
```ruby
# config/routes.rb

# ...

resources :donations
```

### Set Up the Donation Controller
Next, we need to set up the controller for our create view that handles the form data. We'll use the Stripe wrapper to create a charge and save a new donation object. Our controller should contain the following:

```ruby
# app/controllers/donations_controller.rb
 
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
```

### Setting Up the Postcards
Next, we need to set up our templates and `DonationWorker` to actually send our postcards.

#### Setting up the Templates
Let's navigate to [Lob's Dashboard](https://dashboard.lob.com/#/) to set up our postcard templates. We'll be using three different designs corresponding with the amount each user donated. With Lob's templates feature we can use vastly different designs without worrying about their implementation in our application code. 

Let's go ahead and create the four templates we'll be using. We'll have three different front designs and a single back design.

[Screenshot of Creating a Template `template_create.png`]

You can find the HTML for each template below:
* [Donation Back]
* [$10 Donation Front]
* [$20 Donation Front]
* [$50 Donation Front]

**Note:** use the "Preview in Browser" button to check out how each template looks!

[Screenshot of Preview `template_preview.png`]

Now that we've got the templates set up on the dashboard, we need to add their ids to our project. For this, we'll use Figaro again. While we can still edit our templates, their ids will persist across versions so we can feel safe in adding them to our configuration file.

[Screenshot of all four templates `template_list.png`]

Grab the template ids and add the following lines to the `config/application.yml` file. Make sure you've got the corresponding ids for each donation amount --- we don't want to be sending the $10 template to users who donated $50!

```yml
# config/application.yml

# ...

TEMPLATE_BACK: tmpl_xxxxxxxxxxxxxx
TEMPLATE_FRONT_10: tmpl_xxxxxxxxxxxxxx
TEMPLATE_FRONT_20: tmpl_xxxxxxxxxxxxxx
TEMPLATE_FRONT_50: tmpl_xxxxxxxxxxxxxx
```

#### Generate Donation Worker
Next, we'll set up our worker to actually send our postcards through Lob. First, we'll tell Rails to generate a `DonationWorker` for us:
```sh
$ rails generate sidekiq:worker Donation
```

Then, fill in the `app/workers/donation_worker.rb` file with a call to the Lob Postcard API:

```ruby
# app/workers/donation_worker.rb
 
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
```

With the worker all set, we should be ready to get our app up and running!
### Run it
Open up two tabs in your terminal in the `donations-demo` directory and run:
```shell=bash
$ rails s
```
```shell=bash
$ bundle exec sidekiq
```

Navigate to `localhost:3000/donations/new` and create a donation. You should see a new charge created in your Stripe account and a new postcard on your Lob dashboard!

[Screenshots of dashboards `donation_charge.png` and `donation_postcard.png`]

### Wrapping Up
With that, we've got a functioning application that takes donations and automatically sends thank you postcards!

> You can find the full source code for this project [here].

You can check out Lob’s [documentation](https://lob.com/docs) for more information. If you have any additional questions, don’t hesitate to leave a comment below or [contact us](https://lob.com/support#contact) directly. We’re always happy to help! 
