require 'selenium-webdriver'
require 'rmagick'

# Set up Selenium WebDriver with headless mode for Chrome
options = Selenium::WebDriver::Chrome::Options.new
options.add_argument('--headless')  
options.add_argument('--disable-gpu')  
options.add_argument('--window-size=1280x800') 

driver = Selenium::WebDriver.for :chrome, options: options

# Define your API key
api_key = 'c2abc90d5f095aeef1459ae4de37d50edd1b2ed8'

# Concatenate the API key to the URL
url_with_api_key = "http://localhost:3000/project_dashboard?api_key=#{api_key}"

# Navigate to the login page
driver.get('http://localhost:3000/login')

username_field = driver.find_element(id: 'username')
password_field = driver.find_element(id: 'password')

username_field.send_keys('admin') # replace 'your_username' with your actual username
password_field.send_keys('Gola1234@') # replace 'your_password' with your actual password

login_button = driver.find_element(id: 'login-submit')
login_button.click

# wait = Selenium::WebDriver::Wait.new(timeout: 30) # adjust the timeout as needed
# wait.until { driver.current_url == url_with_api_key }

# Once logged in, navigate to the dashboard page
driver.get(url_with_api_key)

csv_btn = driver.find_element(xpath: "//button[contains(., 'Export as CSV')]")
driver.execute_script("arguments[0].click();", csv_btn)

driver.save_screenshot('project_dashboard_after_exports.png')
# Convert the downloaded PNG file to PDF using RMagick
png_file_path = 'project_dashboard_after_exports.png'
pdf_file_path = 'project_dashboard_pdf_generated.pdf'

image = Magick::Image.read(png_file_path).first
image.format = 'PDF'
image.write(pdf_file_path)

driver.quit
