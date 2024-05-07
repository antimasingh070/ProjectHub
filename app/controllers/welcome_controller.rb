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

class WelcomeController < ApplicationController
  self.main_menu = false

  skip_before_action :check_if_login_required, only: [:robots]


  def date_value(project, field_name)
    custom_field = CustomField.find_by(name: field_name)
    custom_value = CustomValue.find_by(customized_type: "Project", customized_id: project&.id, custom_field_id: custom_field&.id)
    date_string = custom_value&.value
end

  def project_dashboard
    @project_status_text = {
      Project::STATUS_ACTIVE => 'Active',
      Project::STATUS_CLOSED => 'Closed',
      Project::STATUS_ARCHIVED => 'Archived',
      Project::STATUS_SCHEDULED_FOR_DELETION => 'Scheduled for Deletion'
    }

    current_user_id = User.current.id

    @projects = Project.where(parent_id: nil)

    @projects = @projects.where("custom_field_value(project, 'Project Category') = ?", params[:category_filter]) if params[:category_filter].present?
    @projects = @projects.where("custom_field_value(project, 'User Function') = ?", params[:function_filter]) if params[:function_filter].present?
    @projects = @projects.where(status: params[:status_filter].to_i) if params[:status_filter].present?
    @projects = @projects.where("project.name = ?", params[:name_filter]) if params[:name_filter].present?
    @projects = @projects.select { |project| member_names(project, 'Project Manager').include?(params[:manager_filter]) } if params[:manager_filter].present?

    if params[:start_date_from].present? && params[:start_date_to].present?
      start_date_range = Date.parse(params[:start_date_from])..Date.parse(params[:start_date_to])
      @projects = @projects.select { |project| start_date_range.cover?(Date.parse(date_value(project, 'Scheduled Start Date'))) }
    end

    if params[:end_date_from].present? && params[:end_date_to].present?
      end_date_range = Date.parse(params[:end_date_from])..Date.parse(params[:end_date_to])
      @projects = @projects.select { |project| end_date_range.cover?(Date.parse(date_value(project, 'Scheduled End Date'))) }
    end

    @projects = @projects.select { |project| project.members.exists?(user_id: current_user_id) }

    @categories = @projects.map { |project| custom_field_value(project, 'Portfolio Category') }.compact.uniq
    @functions = @projects.map { |project| custom_field_value(project, 'User Function') }.compact.uniq
    @statuses = @projects.map { |project| @project_status_text[project.status] }.compact.uniq
    @managers = @projects.flat_map { |project| member_names(project, 'Project Manager') }.compact.uniq

    @names = @projects.map(&:name).compact.uniq
  end

  
  def member_names(project, field_name)
    project_lead_role = Role.find_by(name: field_name)
  
    member_ids_with_lead_role = MemberRole.where(role_id: project_lead_role.id).pluck(:member_id)
    project_lead_user_ids = Member.where(project_id: project.id, id: member_ids_with_lead_role).pluck(:user_id)
  
    if project_lead_user_ids.present?
      project_lead_users = User.where(id: project_lead_user_ids)
      project_lead_names = project_lead_users.pluck(:firstname, :lastname)
      return project_lead_names.map { |firstname, lastname| "#{firstname} #{lastname}" }
    else
      return []
    end
  end  

  def custom_field_value(project, field_name)
    custom_field = CustomField.find_by(name: field_name)
    custom_value = CustomValue.find_by(customized_type: "Project", customized_id: project&.id, custom_field_id: custom_field&.id)
    custom_field_enumeration = CustomFieldEnumeration.find_by(id: custom_value&.value&.to_i)
    custom_field_enumeration&.name
  end

  def index
    @news = News.latest User.current
  end

  def robots
    @projects = Project.visible(User.anonymous) unless Setting.login_required?
    render :layout => false, :content_type => 'text/plain'
  end

  def send_weekly_status_report(format)
    # Generate the weekly status report based on the specified format (csv or pdf)
    report_data = generate_report_data

    case format
    when 'csv'
      generate_csv_report(report_data)
    when 'pdf'
      generate_pdf_report(report_data)
    else
      raise ArgumentError, "Invalid report format: #{format}. Supported formats are 'csv' and 'pdf'."
    end

    # Print a message indicating the report was generated
    puts "Weekly status report generated in #{format} format."
  end

  private

  def generate_report_data
    # Logic to fetch data for the weekly status report
    # This could involve querying the database or any other data source
    # For demonstration purposes, let's return dummy data
    Issue.where(status_id: [1, 2, 3])  # Example: Fetch issues with open, in progress, or re-opened statuses
  end

  def generate_csv_report(report_data)
    # Logic to generate the CSV report
    # For simplicity, let's print the report data
    puts "CSV Report:"
    report_data.each do |issue|
      puts "#{issue.id}, #{issue.subject}, #{issue.status.name}, #{issue.assigned_to&.name}"
    end
  end

  def generate_pdf_report(report_data)
    # Logic to generate the PDF report
    # For simplicity, let's print the report data
    puts "PDF Report:"
    report_data.each do |issue|
      puts "#{issue.id} | #{issue.subject} | #{issue.status.name} | #{issue.assigned_to&.name}"
    end
  end

end

