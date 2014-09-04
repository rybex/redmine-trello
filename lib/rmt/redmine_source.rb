require 'rmt/redmine'
require 'rmt/synchronization_data'

module RMT
  class RedmineSource
    def initialize(redmine_config)
      @redmine_client = RMT::Redmine.new(redmine_config.base_url,
                                         redmine_config.username,
                                         redmine_config.password)
      @project_id = redmine_config.project_id
    end

    def data_for(trello)
      last_update_data = get_last_update_data
      if last_update_data
        target_list = trello.target_list_id
        issues = @redmine_client.get_issues_for_project(@project_id).select {|issue| Time.parse(issue[:updated_on]) >= last_update_data }
        issues_with_comments = issues.collect { |issue| @redmine_client.get_issue_comments(issue[:id], last_update_data)}
        relevant_cards_loader = proc { |trello| trello.list_cards_in(target_list) }
        save_current_date
        issues_with_comments.collect do |ticket|
          SynchronizationData.new(
            ticket[0][:id],
            ticket[0][:subject],
            ticket[0][:description],
            trello.color_map[ticket[0][:tracker]],
            ticket[0][:comments],
            target_list,
            relevant_cards_loader
          )
        end
      else
        []
      end
    end

    private

    def get_last_update_data
      if File.exists?("last_update.txt")
        Time.parse(File.read('last_update.txt'))
      else
        File.new("last_update.txt", "w")
        save_current_date
      end
    end

    def save_current_date
      File.open("last_update.txt","w") {|f| f.write(Time.now) }
      nil
    end
  end
end

