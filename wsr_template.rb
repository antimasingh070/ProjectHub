start_date_previous_week = Date.today.prev_week.beginning_of_week

# Get the end date of the previous week
end_date_previous_week = Date.today.prev_week.end_of_week

# Find closed issues within the previous week
closed_issues_previous_week = Issue.where(closed_on: start_date_previous_week..end_date_previous_week)

# Output the closed issues from the previous week
puts "Closed issues from #{start_date_previous_week} to #{end_date_previous_week}:"
closed_issues_previous_week.each do |issue|
  puts "Issue ID: #{issue.id}, Subject: #{issue.subject}, Closed on: #{issue.closed_on}"
end


# Get the start date (current date)
start_date = Date.today

# Get the end date (current date + 7 days)
end_date = Date.today + 7.days

# Find issues with a due date within the next 7 days
upcoming_due_date_issues = Issue.where(due_date: start_date..end_date)

# Output the issues with due dates within the next 7 days
puts "Issues with due dates from #{start_date} to #{end_date}:"
upcoming_due_date_issues.each do |issue|
  puts "Issue ID: #{issue.id}, Subject: #{issue.subject}, Due Date: #{issue.due_date}"
end
