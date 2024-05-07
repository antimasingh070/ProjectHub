# lib/mailer_script.rb

class MailerScript
    def self.send_issue_email
      user= User.first
  
    #   users.each do |user|
        Mailer.deliver_send_issue_pdf(user, '/Users/user/ProjectHub/app/issues.pdf')
    #   end
    end

    def self.send_dashboard_email
      user= User.first
      Mailer.deliver_send_dashboard_email(user, '/Users/user/ProjectHub/project_dashboard.csv','/Users/user/ProjectHub/project_dashboard_pdf_generated.pdf')
    end

    def self.send_wsr_emails
      user= User.first
      projects = Project.where(status: 1)
      # projects.each do |project|
      project = Project.first
        Mailer.deliver_send_wsr_email(user,project)
        puts "Mail sent for project #{project.name}"
      # end
    end
  end
  