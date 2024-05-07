require 'selenium-webdriver'
require 'mail'
require 'nokogiri'

# Set up Selenium WebDriver with headless mode for Chrome
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument('--headless')
driver = Selenium::WebDriver.for :chrome, options: options

api_key = 'c2abc90d5f095aeef1459ae4de37d50edd1b2ed8'
url_with_api_key = "http://localhost:3000/project_dashboard?api_key=#{api_key}"

driver.get('http://localhost:3000/login')

username_field = driver.find_element(id: 'username')
password_field = driver.find_element(id: 'password')

username_field.send_keys('admin')
password_field.send_keys('Gola1234@') 
login_button = driver.find_element(id: 'login-submit')
login_button.click

driver.get(url_with_api_key)
html_content = driver.page_source

doc = Nokogiri::HTML(html_content)

table = doc.at('div > table')

table_content = table.to_html

driver.quit

table_styles = <<-STYLE
  <style type="text/css">
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th, td {
      padding: 8px;
      border: 1px solid #dddddd;
      text-align: left;
    }
    th {
      background-color: #f2f2f2;
    }
  </style>
STYLE

# Construct the HTML email body with inline CSS
email_body = <<-BODY
  <html>
    <body>
      #{table_styles}
      #{table_content}
      <p>Regards,<br>Name PMO</p>
    </body>
  </html>
BODY

# Configure email settings
Mail.defaults do
  delivery_method :smtp, {
    address: 'smtp.gmail.com',
    port: 587,
    user_name: 'ankitgupta96572@gmail.com',
    password: 'jyuo hxyb xnwn cqew',
    authentication: 'plain'
  }
end

# Create and deliver the email
mail = Mail.new do
  from     'ankigupta96572@gmail.com'
  to       'ankit.gupta.ext@hdbfs.com'
  subject  'Your Table Content'
  html_part do
    content_type 'text/html; charset=UTF-8'
    body email_body
  end
end

mail.deliver!

puts "Email sent with the table content."
