# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-2023  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'roadie'

class Mailer < ActionMailer::Base
  layout 'mailer'
  helper :application
  helper :issues
  helper :custom_fields

  include Redmine::I18n
  include Roadie::Rails::Automatic

  STATUS_ACTIVE     = 1
  STATUS_CLOSED     = 5
  STATUS_ARCHIVED   = 9
  STATUS_SCHEDULED_FOR_DELETION = 10
  STATUS_HOLD = 11
  STATUS_CANCELLED = 12

  STATUS_MAP = {
    STATUS_ACTIVE => "Active",
    STATUS_CLOSED => "Closed",
    STATUS_ARCHIVED => "Archived",
    STATUS_SCHEDULED_FOR_DELETION => "Scheduled for Deletion",
    STATUS_HOLD => "Hold",
    STATUS_CANCELLED => "Cancelled"
  }

  # Overrides ActionMailer::Base#process in order to set the recipient as the current user
  # and his language as the default locale.
  # The first argument of all actions of this Mailer must be a User (the recipient),
  # otherwise an ArgumentError is raised.
  def process(action, *args)
    user = args.first
    raise ArgumentError, "First argument has to be a user, was #{user.inspect}" unless user.is_a?(User)

    initial_user = User.current
    initial_language = ::I18n.locale
    begin
      User.current = user

      lang = find_language(user.language) if user.logged?
      lang ||= Setting.default_language
      set_language_if_valid(lang)

      super(action, *args)
    ensure
      User.current = initial_user
      ::I18n.locale = initial_language
    end
  end

  # Default URL options for generating URLs in emails based on host_name and protocol
  # defined in application settings.
  def self.default_url_options
    options = {:protocol => Setting.protocol}
    if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
      host, port, prefix = $2, $4, $5
      options.merge!(
        {
          :host => host, :port => port, :script_name => prefix
        }
      )
    else
      options[:host] = Setting.host_name
    end
    options
  end

  def issue_send_back(user, issue, auther)
    @user = user
    @issue = issue
    @auther = auther
    @project = @issue.project
    mail_data = user_mails(@project)
    assigned_to_id = @issue.assigned_to_id 
    assignee = User.find_by(id: assigned_to_id) 
    mail_to = []
    mail_to += [@author&.mail, assignee&.mail]
    mail_cc = mail_data[:mail_cc].uniq
    mail :to => mail_to.uniq, :cc => mail_cc.uniq, :subject => "[#{@issue.project.name}] ID: #{@issue.id} Issue send_back: #{@issue.subject}"
  end

  def self.deliver_issue_send_back(user, issue, auther)
    @auther = auther
    @project = issue.project
    @issue = issue
    @user = user
    issue_send_back(user, issue, auther).deliver_later
  end
  
  def issue_approved(user, issue, member_mails)
    @user = user
    @issue = issue
    @author = issue.author
    @member_mails = member_mails
    @project = @issue.project
    mail_data = user_mails(@project)
    assigned_to_id = @issue.assigned_to_id 
    assignee = User.find_by(id: assigned_to_id) 
    mail_to = []
    mail_to += [@author.mail, assignee.mail]
    mail_cc = mail_data[:mail_cc].uniq
    mail :to => mail_to.uniq, :cc => mail_cc.uniq, :subject => "[#{@issue.project.name}] ID: #{@issue.id} Issue Approved: #{@issue.subject}"
  end

  def self.deliver_issue_approved(user, issue, members)
    @members = members
    if  @members.any?
      member_mails = @members.map { |member| member.user.mail }
      @project = issue.project
      @issue = issue
      @user = user
      @project = issue.project
      issue_approved(user, issue, member_mails).deliver_later
    end
  end

  def issue_declined(user, issue, member_mails)
    @user = user
    @issue = issue
    @author = issue.author
    @member_mails = member_mails
    @project = @issue.project
    mail_data = user_mails(@project)
    assigned_to_id = @issue.assigned_to_id 
    assignee = User.find_by(id: assigned_to_id) 
    mail_to = []
    mail_to += [@author.mail, assignee.mail]
    mail_cc = mail_data[:mail_cc].uniq
    mail :to => mail_to.uniq, :cc => mail_cc.uniq, :subject => "[#{@issue.project.name}] ID: #{@issue.id} Issue Declined: #{@issue.subject}"
  end

  def self.deliver_issue_declined(user, issue, members)
    @members = members
    if  @members.any?
      member_mails = @members.map { |member| member.user.mail }
      @project = issue.project
      @issue = issue
      @user = user
      @project = issue.project
      issue_declined(user, issue, member_mails).deliver_later
    end
  end

  # Builds a mail for notifying user about a new issue
  def issue_add(user, issue)
    redmine_headers 'Project' => issue.project.identifier,
                     'Issue-Tracker' => issue.tracker.name,
                     'Issue-Id' => issue.id,
                     'Issue-Author' => issue.author.login,
                     'Issue-Assignee' => assignee_for_header(issue)
     redmine_headers 'Issue-Priority' => issue.priority.name if issue.priority
    message_id issue
    references issue
    @author = issue.author
    @issue = issue
    @user = user
    @project = @issue.project
    mail_data = user_mails(@project)
    assigned_to_id = @issue.assigned_to_id 
    assignee = User.find_by(id: assigned_to_id) 
    custom_field = CustomField.find_by(type: "IssueCustomField", name: "Role")
    custom_value = CustomValue.find_by(customized_type: "Issue", custom_field_id: custom_field.id, customized_id: issue.id)&.value
    # next unlescustom_value 
    custom_field_enumeration = CustomFieldEnumeration.find_by(id: custom_value.to_i, custom_field_id: custom_field.id)&.name 
    matched_role_ids = issue.project.members.joins(:roles).where(roles: { name: custom_field_enumeration }).pluck(:user_id) 
    role_users = User.where(id: matched_role_ids)
    mail_to = []
    if !role_users.blank?
      mail_to += role_users.map(&:mail).uniq
    end
    mail_to += [@author.mail, assignee.mail]
    mail_cc = mail_data[:mail_cc].uniq
    @issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue)
    subject = "[#{issue.project.name} - #{issue.tracker.name} ##{issue.id}]"
    subject += " (#{issue.status.name})" if Setting.show_status_changes_in_mail_subject?
    subject += " #{issue.subject}"
    mail :to => mail_to.uniq, :cc => mail_cc.uniq, :subject => subject
  end

  # Notifies users about a new issue.
  #
  # Example:
  #   Mailer.deliver_issue_add(issue)
  def self.deliver_issue_add(issue)
    user = User.current
    issue_add(user, issue).deliver_later
  end

  # Builds a mail for notifying user about an issue update
  def issue_edit(user, journal)
    issue = journal.journalized
    redmine_headers 'Project' => issue.project.identifier,
                    'Issue-Tracker' => issue.tracker.name,
                    'Issue-Id' => issue.id,
                    'Issue-Author' => issue.author.login,
                    'Issue-Assignee' => assignee_for_header(issue)
    redmine_headers 'Issue-Priority' => issue.priority.name if issue.priority
    message_id journal
    references issue
    @author = journal.user
    @issue = issue
    @project = @issue.project
    mail_data = user_mails(@project)
    assigned_to_id = @issue.assigned_to_id 
    assignee = User.find_by(id: assigned_to_id) 
    custom_field = CustomField.find_by(type: "IssueCustomField", name: "Role")
    custom_value = CustomValue.find_by(customized_type: "Issue", custom_field_id: custom_field.id, customized_id: issue.id)&.value
    # next unlescustom_value 
    custom_field_enumeration = CustomFieldEnumeration.find_by(id: custom_value.to_i, custom_field_id: custom_field.id)&.name 
    matched_role_ids = issue.project.members.joins(:roles).where(roles: { name: custom_field_enumeration }).pluck(:user_id) 
    role_users = User.where(id: matched_role_ids)
    mail_to = []
    if !role_users.blank?
      mail_to += role_users.map(&:mail).uniq
    end
    mail_to += [@author.mail, assignee.mail]
    mail_cc = mail_data[:mail_cc].uniq
    s = "[#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] "
    s += "(#{issue.status.name}) " if journal.new_value_for('status_id') && Setting.show_status_changes_in_mail_subject?
    s += issue.subject
    @issue = issue
    @user = user
    @journal = journal
    @journal_details = journal.visible_details
    @issue_url = url_for(:controller => 'issues', :action => 'show', :id => issue, :anchor => "change-#{journal.id}")
    mail :to => mail_to.uniq, :cc => mail_cc.uniq,
      :subject => s
  end

  # Notifies users about an issue update.
  #
  # Example:
  #   Mailer.deliver_issue_edit(journal)
  def self.deliver_issue_edit(journal)
    users  = journal.notified_users | journal.notified_watchers | journal.notified_mentions | journal.journalized.notified_mentions
    users.select! do |user|
      journal.notes? || journal.visible_details(user).any?
    end
    users.each do |user|
      # issue_edit(user, journal).deliver_later
    end
    user = User.current
    issue_edit(user, journal).deliver_later
  end

  # Builds a mail to user about a new document.
  def document_added(user, document, author)
    redmine_headers 'Project' => document.project.identifier
    @author = author
    @document = document
    @user = user
    @document_url = url_for(:controller => 'documents', :action => 'show', :id => document)
    mail :to => "singhantima720@gmail.com",
    # mail :to => user,
      :subject => "[#{document.project.name}] #{l(:label_document_new)}: #{document.title}"
  end

  # Notifies users that document was created by author
  #
  # Example:
  #   Mailer.deliver_document_added(document, author)
  def self.deliver_document_added(document, author)
    users = document.notified_users
    users.each do |user|
      document_added(user, document, author).deliver_later
    end
  end

  # Builds a mail to user about new attachements.
  def attachments_added(user, attachments)
    container = attachments.first.container
    added_to = ''
    added_to_url = ''
    @author = attachments.first.author
    case container.class.name
    when 'Project'
      added_to_url = url_for(:controller => 'files', :action => 'index', :project_id => container)
      added_to = "#{l(:label_project)}: #{container}"
    when 'Version'
      added_to_url = url_for(:controller => 'files', :action => 'index', :project_id => container.project)
      added_to = "#{l(:label_version)}: #{container.name}"
    when 'Document'
      added_to_url = url_for(:controller => 'documents', :action => 'show', :id => container.id)
      added_to = "#{l(:label_document)}: #{container.title}"
    end
    redmine_headers 'Project' => container.project.identifier
    @attachments = attachments
    @user = user
    @added_to = added_to
    @added_to_url = added_to_url
    mail :to => "singhantima720@gmail.com",
    # mail :to => user,
      :subject => "[#{container.project.name}] #{l(:label_attachment_new)}"
  end

  # Notifies users about new attachments
  #
  # Example:
  #   Mailer.deliver_attachments_added(attachments)
  def self.deliver_attachments_added(attachments)
    container = attachments.first.container
    case container.class.name
    when 'Project', 'Version'
      users = container.project.notified_users.select {|user| user.allowed_to?(:view_files, container.project)}
    when 'Document'
      users = container.notified_users
    end

    users.each do |user|
      attachments_added(user, attachments).deliver_later
    end
  end

  # Builds a mail to user about a new news.
  def news_added(user, news)
    redmine_headers 'Project' => news.project.identifier
    @author = news.author
    @project = news.project
    message_id news
    references news
    @news = news
    @user = user
    @project_status =   STATUS_MAP[@project.status] || "Unknown"
    mail_data = user_mails(@project)
    mail_to = mail_data[:mail_to].uniq
    mail_cc = mail_data[:mail_cc].uniq
    @news_url = url_for(:controller => 'news', :action => 'show', :id => news)
    mail :to => mail_to,  cc: mail_cc, :subject => "[ProjectHUB] Project NEWS: #{news.project.name}  #{news.project.identifier}"
  end
  
  # Notifies users about new news
  #
  # Example:
  #   Mailer.deliver_news_added(news)
  def self.deliver_news_added(news)
    # users = news.notified_users | news.notified_watchers_for_added_news
    # users.each do |user|
    #   news_added(user, news).deliver_later
    # end
    user = User.current
    news_added(user, news).deliver_later
  end

  # Builds a mail to user about a new news comment.
  def news_comment_added(user, comment)
    news = comment.commented
    redmine_headers 'Project' => news.project.identifier
    @author = comment.author
    message_id comment
    references news
    @news = news
    @comment = comment
    @user = user
    @news_url = url_for(:controller => 'news', :action => 'show', :id => news)
    mail :to => user,
     :subject => "Re: [ProjectHUB] Project NEWS: #{news.project.name} #{news.project.identifier}"
  end

  # Notifies users about a new comment on a news
  #
  # Example:
  #   Mailer.deliver_news_comment_added(comment)
  def self.deliver_news_comment_added(comment)
    news = comment.commented
    users = news.notified_users | news.notified_watchers
    users.each do |user|
      # news_comment_added(user, comment).deliver_later
    end
    news_comment_added(users, comment).deliver_later
  end

  # Builds a mail to user about a new message.
  def message_posted(user, message)
    redmine_headers 'Project' => message.project.identifier,
                    'Topic-Id' => (message.parent_id || message.id)
    @author = message.author
    message_id message
    references message.root
    @message = message
    @user = user
    @message_url = url_for(message.event_url)
    mail :to => user,
      :subject => "[#{message.board.project.name} - #{message.board.name} - msg#{message.root.id}] #{message.subject}"
  end

  # Notifies users about a new forum message.
  #
  # Example:
  #   Mailer.deliver_message_posted(message)
  def self.deliver_message_posted(message)
    users  = message.notified_users
    users |= message.root.notified_watchers
    users |= message.board.notified_watchers

    users.each do |user|
      # message_posted(user, message).deliver_later
    end
    message_posted(users, message).deliver_later
  end

  # Builds a mail to user about a new wiki content.
  def wiki_content_added(user, wiki_content)
    redmine_headers 'Project' => wiki_content.project.identifier,
                    'Wiki-Page-Id' => wiki_content.page.id
    @author = wiki_content.author
    message_id wiki_content
    @wiki_content = wiki_content
    @user = user
    @wiki_content_url = url_for(:controller => 'wiki', :action => 'show',
                                      :project_id => wiki_content.project,
                                      :id => wiki_content.page.title)
    mail(
      :to => user,
      :subject =>
        "[#{wiki_content.project.name}] #{l(:mail_subject_wiki_content_added, :id => wiki_content.page.pretty_title)}"
    )
  end

  # Notifies users about a new wiki content (wiki page added).
  #
  # Example:
  #   Mailer.deliver_wiki_content_added(wiki_content)
  def self.deliver_wiki_content_added(wiki_content)
    users = wiki_content.notified_users | wiki_content.page.wiki.notified_watchers | wiki_content.notified_mentions
    users.each do |user|
      # wiki_content_added(user, wiki_content).deliver_later
    end
    wiki_content_added(users, wiki_content).deliver_later
  end

  # Builds a mail to user about an update of the specified wiki content.
  def wiki_content_updated(user, wiki_content)
    redmine_headers 'Project' => wiki_content.project.identifier,
                    'Wiki-Page-Id' => wiki_content.page.id
    @author = wiki_content.author
    message_id wiki_content
    @wiki_content = wiki_content
    @user = user
    @wiki_content_url =
      url_for(:controller => 'wiki', :action => 'show',
              :project_id => wiki_content.project,
              :id => wiki_content.page.title)
    @wiki_diff_url =
      url_for(:controller => 'wiki', :action => 'diff',
              :project_id => wiki_content.project, :id => wiki_content.page.title,
              :version => wiki_content.version)
    mail(
      :to => user,
      :subject =>
        "[#{wiki_content.project.name}] #{l(:mail_subject_wiki_content_updated, :id => wiki_content.page.pretty_title)}"
    )
  end

  # Notifies users about the update of the specified wiki content
  #
  # Example:
  #   Mailer.deliver_wiki_content_updated(wiki_content)
  def self.deliver_wiki_content_updated(wiki_content)
    users  = wiki_content.notified_users
    users |= wiki_content.page.notified_watchers
    users |= wiki_content.page.wiki.notified_watchers
    users |= wiki_content.notified_mentions

    users.each do |user|
      wiki_content_updated(user, wiki_content).deliver_later
    end
  end

  # Builds a mail to user about his account information.
  def account_information(user, password)
    @user = user
    @password = password
    @login_url = url_for(:controller => 'account', :action => 'login')
    mail :to => user.mail,
      :subject => l(:mail_subject_register, Setting.app_title)
  end

  # Notifies user about his account information.
  def self.deliver_account_information(user, password)
    account_information(user, password).deliver_later
  end

  # Builds a mail to user about an account activation request.
  def account_activation_request(user, new_user)
    @new_user = new_user
    @url = url_for(:controller => 'users', :action => 'index',
                         :status => User::STATUS_REGISTERED,
                         :sort_key => 'created_on', :sort_order => 'desc')
                         mail :to => user,
      :subject => l(:mail_subject_account_activation_request, Setting.app_title)
  end

  # Notifies admin users that an account activation request needs
  # their approval.
  #
  # Exemple:
  #   Mailer.deliver_account_activation_request(new_user)
  def self.deliver_account_activation_request(new_user)
    # Send the email to all active administrators
    users = User.active.where(:admin => true)
    users.each do |user|
      account_activation_request(user, new_user).deliver_later
    end
  end

  # Builds a mail to notify user that his account was activated.
  def account_activated(user)
    @user = user
    @login_url = url_for(:controller => 'account', :action => 'login')
    mail :to => user.mail,
      :subject => l(:mail_subject_register, Setting.app_title)
  end

  # Notifies user that his account was activated.
  #
  # Exemple:
  #   Mailer.deliver_account_activated(user)
  def self.deliver_account_activated(user)
    account_activated(user).deliver_later
  end

  # Builds a mail with the password recovery link.
  def lost_password(user, token, recipient=nil)
    recipient ||= user.mail
    @token = token
    @url = url_for(:controller => 'account', :action => 'lost_password', :token => token.value)
    mail :to => recipient,
      :subject => l(:mail_subject_lost_password, Setting.app_title)
  end

  # Sends an email to user with a password recovery link.
  # The email will be sent to the email address specifiedby recipient if provided.
  #
  # Exemple:
  #   Mailer.deliver_lost_password(user, token)
  #   Mailer.deliver_lost_password(user, token, 'foo@example.net')
  def self.deliver_lost_password(user, token, recipient=nil)
    lost_password(user, token, recipient).deliver_later
  end

  # Notifies user that his password was updated by sender.
  #
  # Exemple:
  #   Mailer.deliver_password_updated(user, sender)
  def self.deliver_password_updated(user, sender)
    # Don't send a notification to the dummy email address when changing the password
    # of the default admin account which is required after the first login
    # TODO: maybe not the best way to handle this
    return if user.admin? && user.login == 'admin' && user.mail == 'admin@example.net'

    deliver_security_notification(
      user,
      sender,
      message: :mail_body_password_updated,
      title: :button_change_password,
      url: {controller: 'my', action: 'password'}
    )
  end

  # Builds a mail to user with his account activation link.
  def register(user, token)
    @token = token
    @url = url_for(:controller => 'account', :action => 'activate', :token => token.value)
    mail :to => user.mail,
      :subject => l(:mail_subject_register, Setting.app_title)
  end

  # Sends an mail to user with his account activation link.
  #
  # Exemple:
  #   Mailer.deliver_register(user, token)
  def self.deliver_register(user, token)
    register(user, token).deliver_later
  end

  # Build a mail to user and the additional recipients given in
  # options[:recipients] about a security related event made by sender.
  #
  # Example:
  #   security_notification(user,
  #     sender,
  #     message: :mail_body_security_notification_add,
  #     field: :field_mail,
  #     value: address
  #   ) => Mail::Message object
  def security_notification(user, sender, options={})
    @user = user
    @sender = sender
    redmine_headers 'Sender' => sender.login
    @message =
      l(options[:message],
        field: (options[:field] && l(options[:field])),
        value: options[:value])
    @title = options[:title] && l(options[:title])
    @remote_ip = options[:remote_ip] || @sender.remote_ip
    @url = options[:url] && (options[:url].is_a?(Hash) ? url_for(options[:url]) : options[:url])
    redmine_headers 'Url' => @url
    mail :to => [user, *options[:recipients]].uniq,
      :subject => "[#{Setting.app_title}] #{l(:mail_subject_security_notification)}"
  end

  # Notifies the given users about a security related event made by sender.
  #
  # You can specify additional recipients in options[:recipients]. These will be
  # added to all generated mails for all given users. Usually, you'll want to
  # give only a single user when setting the additional recipients.
  #
  # Example:
  #   Mailer.deliver_security_notification(users,
  #     sender,
  #     message: :mail_body_security_notification_add,
  #     field: :field_mail,
  #     value: address
  #   )
  def self.deliver_security_notification(users, sender, options={})
    # Symbols cannot be serialized:
    # ActiveJob::SerializationError: Unsupported argument type: Symbol
    options = options.transform_values {|v| v.is_a?(Symbol) ? v.to_s : v}
    # sender's remote_ip would be lost on serialization/deserialization
    # we have to pass it with options
    options[:remote_ip] ||= sender.remote_ip

    Array.wrap(users).each do |user|
      security_notification(user, sender, options).deliver_later
    end
  end

  # Build a mail to user about application settings changes made by sender.
  def settings_updated(user, sender, changes, options={})
    @sender = sender
    redmine_headers 'Sender' => sender.login
    @changes = changes
    @remote_ip = options[:remote_ip] || @sender.remote_ip
    @url = url_for(controller: 'settings', action: 'index')
    mail :to => user,
      :subject => "[#{Setting.app_title}] #{l(:mail_subject_security_notification)}"
  end

  # Notifies admins about application settings changes made by sender, where
  # changes is an array of settings names.
  #
  # Exemple:
  #   Mailer.deliver_settings_updated(sender, [:login_required, :self_registration])
  def self.deliver_settings_updated(sender, changes, options={})
    return unless changes.present?

    # Symbols cannot be serialized:
    # ActiveJob::SerializationError: Unsupported argument type: Symbol
    changes = changes.map(&:to_s)
    # sender's remote_ip would be lost on serialization/deserialization
    # we have to pass it with options
    options[:remote_ip] ||= sender.remote_ip

    users = User.active.where(admin: true).to_a
    users.each do |user|
      settings_updated(user, sender, changes, options).deliver_later
    end
  end

  # Build a test email to user.
  def test_email(user)
    @url = url_for(:controller => 'welcome')
    mail :to => user,
      :subject => 'Redmine test'
  end

  # Send a test email to user. Will raise error that may occur during delivery.
  #
  # Exemple:
  #   Mailer.deliver_test_email(user)
  def self.deliver_test_email(user)
    raise_delivery_errors_was = self.raise_delivery_errors
    self.raise_delivery_errors = true
    # Email must be delivered synchronously so we can catch errors
    # test_email(user).deliver_later
    project_created(User.first, Project.first).deliver_later
  ensure
    self.raise_delivery_errors = raise_delivery_errors_was
  end

  # Builds a reminder mail to user about issues that are due in the next days.
  def reminder(user, issues, days)
    @issues = issues
    @days = days
    @open_issues_url = url_for(:controller => 'issues', :action => 'index',
                                :set_filter => 1, :assigned_to_id => 'me',
                                :sort => 'due_date:asc')
    @reminder_issues_url = url_for(:controller => 'issues', :action => 'index',
      :set_filter => 1, :sort => 'due_date:asc',
      :f => ['status_id', 'assigned_to_id', "due_date"],
      :op => {'status_id' => 'o', 'assigned_to_id' => '=', 'due_date' => '<t+'},
      :v =>{'assigned_to_id' => ['me'], 'due_date' => [days]})

    query = IssueQuery.new(:name => '_')
    query.add_filter('assigned_to_id', '=', ['me'])
    @open_issues_count = query.issue_count
    mail :to => user,
      :subject => l(:mail_subject_reminder, :count => issues.size, :days => days)
  end

  # Sends reminders to issue assignees
  # Available options:
  # * :days     => how many days in the future to remind about (defaults to 7)
  # * :tracker  => id of tracker for filtering issues (defaults to all trackers)
  # * :project  => id or identifier of project to process (defaults to all projects)
  # * :users    => array of user/group ids who should be reminded
  # * :version  => name of target version for filtering issues (defaults to none)
  def self.reminders(options={})
    days = options[:days] || 7
    project = options[:project] ? Project.find(options[:project]) : nil
    tracker = options[:tracker] ? Tracker.find(options[:tracker]) : nil
    target_version_id = options[:version] ? Version.named(options[:version]).pluck(:id) : nil
    if options[:version] && target_version_id.blank?
      raise ActiveRecord::RecordNotFound.new("Couldn't find Version named #{options[:version]}")
    end

    user_ids = options[:users]

    scope =
      Issue.open.where(
        "#{Issue.table_name}.assigned_to_id IS NOT NULL" \
          " AND #{Project.table_name}.status = #{Project::STATUS_ACTIVE}" \
          " AND #{Issue.table_name}.due_date <= ?", days.day.from_now.to_date
      )
    scope = scope.where(:assigned_to_id => user_ids) if user_ids.present?
    scope = scope.where(:project_id => project.id) if project
    scope = scope.where(:fixed_version_id => target_version_id) if target_version_id.present?
    scope = scope.where(:tracker_id => tracker.id) if tracker
    issues_by_assignee = scope.includes(:status, :assigned_to, :project, :tracker).
                              group_by(&:assigned_to)
    issues_by_assignee.keys.each do |assignee|
      if assignee.is_a?(Group)
        assignee.users.each do |user|
          issues_by_assignee[user] ||= []
          issues_by_assignee[user] += issues_by_assignee[assignee]
        end
      end
    end

    issues_by_assignee.each do |assignee, issues|
      if assignee.is_a?(User) && assignee.active? && issues.present?
        visible_issues = issues.select {|i| i.visible?(assignee)}
        visible_issues.sort!{|a, b| (a.due_date <=> b.due_date).nonzero? || (a.id <=> b.id)}
        reminder(assignee, visible_issues, days).deliver_later if visible_issues.present?
      end
    end
  end

  # Activates/desactivates email deliveries during +block+
  def self.with_deliveries(enabled = true, &block)
    was_enabled = ActionMailer::Base.perform_deliveries
    ActionMailer::Base.perform_deliveries = !!enabled
    yield
  ensure
    ActionMailer::Base.perform_deliveries = was_enabled
  end

  # Execute the given block with inline sending of emails if the default Async
  # queue is used for the mailer. See the Rails guide:
  # Using the asynchronous queue from a Rake task will generally not work because
  # Rake will likely end, causing the in-process thread pool to be deleted, before
  # any/all of the .deliver_later emails are processed
  def self.with_synched_deliveries(&block)
    adapter = ActionMailer::MailDeliveryJob.queue_adapter
    ActionMailer::MailDeliveryJob.queue_adapter = ActiveJob::QueueAdapters::InlineAdapter.new
    yield
  ensure
    ActionMailer::MailDeliveryJob.queue_adapter = adapter
  end

  def mail(headers={}, &block)
    # Add a display name to the From field if Setting.mail_from does not
    # include it
    begin
      mail_from = Mail::Address.new(Setting.mail_from)
      if mail_from.display_name.blank? && mail_from.comments.blank?
        mail_from.display_name =
          @author&.logged? ? @author.name : Setting.app_title
      end
      from = mail_from.format
      list_id = "<#{mail_from.address.to_s.tr('@', '.')}>"
    rescue Mail::Field::IncompleteParseError
      # Use Setting.mail_from as it is if Mail::Address cannot parse it
      # (probably the emission address is not RFC compliant)
      from = Setting.mail_from.to_s
      list_id = "<#{from.tr('@', '.')}>"
    end

    headers.reverse_merge! 'X-Mailer' => 'Redmine',
            'X-Redmine-Host' => Setting.host_name,
            'X-Redmine-Site' => Setting.app_title,
            'X-Auto-Response-Suppress' => 'All',
            'Auto-Submitted' => 'auto-generated',
            'From' => from,
            'List-Id' => list_id

    # Replaces users with their email addresses
    [:to, :cc, :bcc].each do |key|
      if headers[key].present?
        headers[key] = self.class.email_addresses(headers[key])
      end
    end

    # Removes the author from the recipients and cc
    # if the author does not want to receive notifications
    # about what the author do
    if @author&.logged? && @author.pref.no_self_notified
      addresses = @author.mails
      headers[:to] -= addresses if headers[:to].is_a?(Array)
      headers[:cc] -= addresses if headers[:cc].is_a?(Array)
    end

    if @author&.logged?
      redmine_headers 'Sender' => @author.login
    end

    if @message_id_object
      headers[:message_id] = "<#{self.class.message_id_for(@message_id_object, @user)}>"
    end
    if @references_objects
      headers[:references] = @references_objects.collect {|o| "<#{self.class.references_for(o, @user)}>"}.join(' ')
    end

    if block
      super headers, &block
    else
      super headers do |format|
        format.text
        format.html unless Setting.plain_text_mail?
      end
    end
  end

  def self.deliver_mail(mail)
    return false if mail.to.blank? && mail.cc.blank? && mail.bcc.blank?

    begin
      # Log errors when raise_delivery_errors is set to false, Rails does not
      mail.raise_delivery_errors = true
      super
    rescue => e
      if ActionMailer::Base.raise_delivery_errors
        raise e
      else
        Rails.logger.error "Email delivery error: #{e.message}"
      end
    end
  end

  # Returns an array of email addresses to notify by
  # replacing users in arg with their notified email addresses
  #
  # Example:
  #   Mailer.email_addresses(users)
  #   => ["foo@example.net", "bar@example.net"]
  def self.email_addresses(arg)
    arr = Array.wrap(arg)
    mails = arr.reject {|a| a.is_a? Principal}
    users = arr - mails
    if users.any?
      mails += EmailAddress.
        where(:user_id => users.map(&:id)).
        where("is_default = ? OR notify = ?", true, true).
        pluck(:address)
    end
    mails
  end

  def project_created(user, member_role, role, project)
    @project = project
    @user = user
    @member_role = member_role
    @role = role
    # @url = url_for(:controller => 'account', :action => 'activate', :token => token.value)
    mail :to => user.mail,
      :subject => "Project Created"
  end
  
  def self.deliver_project_created(user, project)
    @members = Member.where(project_id: project.id)
    if  @members.any?
      @members.each do |member|
        @member_role = MemberRole.find_by(member_id: member.id)
        @role = Role.find_by(id: @member_role.role_id)
        @user = User.find(member.user.id) if member.user.present?
        @project = project
      end
      project_created(@user, @member_role, @role, @project).deliver_later
    end
  end

  def project_updated(user, member_role, role, project, updated_fields)
    @project = project
    @user = user
    @member_role = member_role
    @role = role
    @updated_fields = updated_fields
    mail_data = user_mails(@project)
    mail_to = mail_data[:mail_to].uniq
    mail_cc = mail_data[:mail_cc].uniq
    mail :to => mail_to, :cc => mail_cc, 
      :subject => "Project Updated"
  end

  def self.deliver_project_updated(user, project, updated_fields)
    @members = Member.where(project_id: project.id)
    if  @members.any?
      @members.each do |member|
        @member_role = MemberRole.find_by(member_id: member.id)
        @role = Role.find_by(id: @member_role.role_id)
        @user = User.find(member.user.id) if member.user.present?
        @project = project
      end
      project_updated(@user, @member_role, @role, @project, updated_fields).deliver_later
    end
  end

  def project_status(user, old_status, project)
    @user = user
    @project = project
    @old_status = old_status
    @new_status = @project.status
    @old_status_text = STATUS_MAP[old_status] || "Unknown"
    @new_status_text = STATUS_MAP[@project.status] || "Unknown"
  
    mail_data = user_mails(@project)
    mail_to = mail_data[:mail_to].uniq
    mail_cc = mail_data[:mail_cc].uniq
    mail_subject = "[ProjectHUB] #{project.name} has been updated from \"#{@old_status_text}\" to \"#{@new_status_text}\" on #{Time.now.strftime("%B %d, %Y")}"
  
    mail(to: mail_to, cc: mail_cc, subject: mail_subject)
  end
  

  def self.deliver_project_status(user, old_status, project)
    project_status(user, old_status, project).deliver_later
  end

  def membership_added_email(user, project)
    @user = user
    @project = project
    mail_data = user_mails(@project)
    mail_to = mail_data[:mail_to].uniq
    mail_cc = mail_data[:mail_cc].uniq
    mail(to: mail_to, cc: mail_cc, subject: "[ProjectHUB] New Project Created: #{project.name} #{project.identifier}")    
  end

  def self.deliver_membership_added_email(user, project)
    membership_added_email(user, project).deliver_later
  end

  def membership_deleted_email(user, role, project)
    @user = user
    @role = role
    @project = project
<<<<<<< HEAD
    mail :to => user.mail,
      :subject => "[ProjectHUB] Project update: #{@project.name}  #{@project.identifier}"
=======
    mail_data = user_mails(@project)
    mail_to = mail_data[:mail_to].uniq
    mail_cc = mail_data[:mail_cc].uniq
    mail(to: mail_to, cc: mail_cc, 
      :subject => "[ProjectHUB] New Project Created: #{@project.name}  #{@project.identifier} ")
>>>>>>> a0c06d16bf8774c0c0e052fffb00ec9749ed7cb3
  end

  def self.deliver_membership_deleted_email(user, role, project)
    membership_deleted_email(user, role, project).deliver_later
  end

  def send_issue_pdf(user, file_path)
    attachments['issue.pdf'] = File.read(file_path, mode: 'rb')
    mail(to: "ankitguptalu9@gmail.com", subject: 'New Project Created')
  end

  def self.deliver_send_issue_pdf(user, file_path)
    send_issue_pdf(user, file_path).deliver_now
  end

  def send_dashboard_email(user, projects)
    # attachments['project_dashboard.csv'] = File.read(csv_path, mode: 'rb')
    # attachments['project_dashboard_pdf_generated.pdf'] = File.read(pdf_path, mode: 'rb')
    @projects= projects
    mail(to: "ankitguptalu9@gmail.com", subject: 'New Dashboard Data')
  end
  def self.deliver_send_dashboard_email(user, projects)
    send_dashboard_email(user, projects).deliver_now
  end
 
  def send_wsr_email(user,project)
    @project = project
    @members = Member.where(project_id: @project.id)
    
    if @members.any?
      @members.each do |member|
        @member_role = MemberRole.find_by(member_id: member.id)
        @role = Role.find_by(id: @member_role.role_id)
        @user = User.find(member.user_id)
      end
    end

    # Adjust the recipient of the email based on project or member data
    @recipient_email = @members.pluck(:user_id).map { |user_id| User.find(user_id).mail }.join(",") # Pluck emails of all project members
    
    mail(to: "ankit.gupta.ext@hdbfs.com", subject: 'New Dashboard Data')  
  end

  def self.deliver_send_wsr_email(user,projects)
    if Setting.notified_events.include?('send_wsr_email')
      send_wsr_email(user,projects).deliver_now
    end
  end 

  def send_issue_list(user, project, issues)
    @project = project
    @members = Member.where(project_id: @project.id)
    @issues = issues
    if @members.any?
      @members.each do |member|
        @member_role = MemberRole.find_by(member_id: member.id)
        @role = Role.find_by(id: @member_role.role_id)
        @user = User.find(member.user_id)
      end
    end

    # Adjust the recipient of the email based on project or member data
    @recipient_email = @members.pluck(:user_id).map { |user_id| User.find(user_id).mail }.join(",") # Pluck emails of all project members
    
    mail(to: "ankitguptalu9@gmail.com", subject: 'Issue List')
  end

  def self.deliver_send_issue_list(user, project,overdue_issues)
    if overdue_issues.any?
      send_issue_list(user, project, overdue_issues).deliver_now
    end
  end
  
  private

  def user_mails(project)
    @project = project
    existing_members = @project.members.pluck(:id)
    project_managers = fetch_project_manager(existing_members)
    program_managers = fetch_program_managers(existing_members)
    pmo = fetch_pmo(existing_members)
    all_user_ids = fetch_all_project_members(project_managers.pluck(:id), program_managers.pluck(:id), pmo.pluck(:id), existing_members, project)
    recipient_ids = project_managers.pluck(:id) + program_managers.pluck(:id) + pmo.pluck(:id)
    mail_to = []
    mail_cc = []
    @user = User.current
    if !all_user_ids.include?(@user.id) || !recipient_ids.include?(@user.id)
      mail_to << @user.mail
    end
    mail_to += User.where(id: all_user_ids).pluck(:id).map { |id| User.find(id).mail }
    recipient_users = User.where(id: recipient_ids)
    mail_cc = recipient_users.map(&:mail).uniq
    { mail_to: mail_to, mail_cc: mail_cc }
  end

  def fetch_all_project_members(project_managers, program_managers, pmo, existing_members, project)
    existing_member_ids = existing_members
    existing_user_ids = existing_member_ids.map { |member_id| Member.find(member_id).user.id }
    all_recipients = [project_managers, program_managers, pmo].flatten.uniq
    new_user_ids = existing_user_ids.reject { |id| all_recipients.include?(id) }
  end

  def fetch_members_by_role(existing_members, role_name)
    role = Role.find_by(name: role_name)
    members_with_role = existing_members.select { |member_id| MemberRole.find_by(member_id: member_id, role_id: role.id) }
    members_with_role.map { |member_id| Member.find(member_id).user }
  end

  def fetch_project_manager(existing_members)
    fetch_members_by_role(existing_members, "Project Manager")
  end
  
  def fetch_program_managers(existing_members)
    fetch_members_by_role(existing_members, "Program Manager")
  end
  
  def fetch_pmo(existing_members)
    fetch_members_by_role(existing_members, "pmo")
  end

  # Appends a Redmine header field (name is prepended with 'X-Redmine-')
  def redmine_headers(h)
    h.compact.each {|k, v| headers["X-Redmine-#{k}"] = v.to_s}
  end

  def assignee_for_header(issue)
    case issue.assigned_to
    when User
      issue.assigned_to.login
    when Group
      "Group (#{issue.assigned_to.name})"
    end
  end

  # Singleton class method is public
  class << self
    def token_for(object, user)
      timestamp = object.send(object.respond_to?(:created_on) ? :created_on : :updated_on)
      hash = [
        "redmine",
        "#{object.class.name.demodulize.underscore}-#{object.id}",
        timestamp.utc.strftime("%Y%m%d%H%M%S")
      ]
      hash << user.id if user
      host = Setting.mail_from.to_s.strip.gsub(%r{^.*@|>}, '')
      host = "#{::Socket.gethostname}.redmine" if host.empty?
      "#{hash.join('.')}@#{host}"
    end

    # Returns a Message-Id for the given object
    def message_id_for(object, user)
      token_for(object, user)
    end

    # Returns a uniq token for a given object referenced by all notifications
    # related to this object
    def references_for(object, user)
      token_for(object, user)
    end
  end

  def message_id(object)
    @message_id_object = object
  end

  def references(object)
    @references_objects ||= []
    @references_objects << object
  end
end