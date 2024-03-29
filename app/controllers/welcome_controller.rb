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

  def send_weekly_report
    report_type = params[:reportType]

    # Logic to generate the CSV or PDF file
    file_path = generate_report_file(report_type)

    # Logic to send email with the file attached
    UserMailer.send_weekly_report(file_path).deliver_now

    head :ok
  end



  def project_dashboard
    @project_status_text = {
      Project::STATUS_ACTIVE => 'Active',
      Project::STATUS_CLOSED => 'Closed',
      Project::STATUS_ARCHIVED => 'Archived',
      Project::STATUS_SCHEDULED_FOR_DELETION => 'Scheduled for Deletion'
    }
  
    current_user_id = User.current.id
  
    # Filter projects based on various conditions
    if params[:function_filter].present? && params[:category_filter].present?
      @projects = Project.where(parent_id: nil)
                         .select { |project| custom_field_value(project, "Project Category") == params[:category_filter] && custom_field_value(project, "User Function") == params[:function_filter] && project.members.exists?(user_id: current_user_id) }
    elsif params[:function_filter].present?
      @projects = Project.where(parent_id: nil)
                         .select { |project| custom_field_value(project, "User Function") == params[:function_filter] && project.members.exists?(user_id: current_user_id) }
    elsif params[:category_filter].present?
      @projects = Project.where(parent_id: nil)
                         .select { |project| custom_field_value(project, "Project Category") == params[:category_filter] && project.members.exists?(user_id: current_user_id) }
    elsif params[:status_filter].present?
      @projects = Project.where(parent_id: nil)
                         .select { |project| project.status == params[:status_filter].to_i && project.members.exists?(user_id: current_user_id) }
    elsif params[:name_filter].present?
      @projects = Project.where(parent_id: nil)
                         .select { |project| project.name == params[:name_filter].to_s && project.members.exists?(user_id: current_user_id) }
    elsif params[:manager_filter].present?
      manager_filter = params[:manager_filter].strip
      @projects = Project.where(parent_id: nil)
                         .select do |project|
                           member_names = member_name(project, "Project Manager")
                           member_names.any? { |name| name.include?(manager_filter) } && project.members.exists?(user_id: current_user_id)
                         end
    else
      # Default case: show projects where the current user is a member
      @projects = Project.where(parent_id: nil)
                         .select { |project| project.members.exists?(user_id: current_user_id) }
    end  

    @categories = @projects.map { |project| custom_field_value(project, "Portfolio Category") }.uniq.compact
    @functions = @projects.map { |project| custom_field_value(project, "User Function") }.uniq.compact
    @statuses = @projects.map { |project| @project_status_text[project.status]}.uniq.compact
    @manageres = @projects.map { |project| member_name(project, "Project Manager") }.flatten.compact.map { |name| name.split(',').map(&:strip) }.flatten.uniq
    @names = @projects.map { |project| project.name  }.uniq.compact
    
  end
  
  def member_name(project, field_name)
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

  private

  def generate_report_file(report_type)
    # Logic to generate the CSV or PDF file
    # ...

    file_path = "/path/to/generated/file.#{report_type}"
    # ...

    file_path
  end
end
