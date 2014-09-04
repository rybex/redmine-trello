require 'faraday'
require 'ox'

# A class for reading data from a redmine instance via the REST API.
# There are several gems that purport to be able to do this, and you
# are also supposed to be able to do it directly via ActiveResource;
# However, I kept getting xml type conversion errors with all of them
# and eventually got sick of battling with them, when what we needed
# to accomplish is really easy to just write from scratch.
module RMT
  class Redmine

    # Instantiate a redmine client
    #
    # @param [String] base_url the base url (e.g., "https://projects.puppetlabs.com") of the redmine project site to read issues from
    # @param [String] username optional username if authentication is needed.  defaults to nil.
    # @param [String] password optional username if authentication is needed.  defaults to nil.
    def initialize(base_url, username = nil, password = nil)
      @base_url = base_url.sub(/\/$/, "")
      @conn = Faraday.new

      if (username and password)
        @conn.basic_auth(username, password)
      end
    end

    # Get a list of issues for a given project id
    #
    # @param [String] project_id the id of the Redmine project.  You can find this easily by just
    #  pointing your browser to "<base_url>/projects.xml"
    # @param [Hash] options optional hash of extra options for filtering results.  Currently supported:
    #    * :created_date_range : a two-element array where the first element is a String representation of a
    #        start date (in the format "YYYY-MM-DD"), and the second element is a String representation of an
    #        end date.  Either may be nil; if this option is specified, results will be filtered according to
    #        the "created_on" field of the redmine issues.
    # @return [Array] an array of Hashes.  Each item in the array represents an issue from redmine.  Each
    #   issue hash contains the following keys:
    #    * :id
    #    * :subject
    #    * :description
    #    * :start_date
    #    * :due_date
    #    * :done_ratio
    #    * :estimated_hours
    #    * :description
    #    * :created_on
    #    * :updated_on
    #    * :tracker
    #    * :status
    #    * :priority
    #    * :author
    def get_issues_for_project(project_id)
      uri = "#{@base_url}/issues.xml?project_id=#{project_id}&limit=1000"
      response = @conn.get(uri)
      parse_issues(response.body).find_all &not_in_subproject_of(project_id)
    end

    def get_issue_comments(issue_id, last_sync_date)
      uri = "#{@base_url}/issues/#{issue_id}.xml?include=journals"
      response = @conn.get(uri)
      parse_issues(response.body, last_sync_date)
    end

    ###########################################################################
    # Private utility methods
    ###########################################################################

    def not_in_subproject_of(project_id)
      proc { |issue| issue[:project_id] == project_id }
    end

    # parse the http response body (xml) and return a list of issues
    def parse_issues(response_body, last_sync_date = nil)
      if last_sync_date
        Ox.parse(response_body).nodes.collect &get_formatted_issue(last_sync_date)
      else
        Ox.parse(response_body).root.nodes.collect &get_formatted_issue(last_sync_date)
      end
    end
    private

    def get_formatted_issue(last_sync_date)
      proc { |issue_node| {
          id: get_value_of_text_child_node(issue_node, "id"),
          subject: get_value_of_text_child_node(issue_node, "subject"),
          description: get_issue_description(issue_node),
          start_date: get_value_of_text_child_node(issue_node, "start_date"),
          due_date: get_value_of_text_child_node(issue_node, "due_date"),
          done_ratio: get_value_of_text_child_node(issue_node, "done_ratio"),
          estimated_hours: get_value_of_text_child_node(issue_node, "estimated_hours"),
          created_on: get_value_of_text_child_node(issue_node, "created_on"),
          updated_on: get_value_of_text_child_node(issue_node, "updated_on"),
          tracker: get_attribute_of_child_node(issue_node, "tracker", :name),
          status: get_attribute_of_child_node(issue_node, "status", :name),
          priority: get_attribute_of_child_node(issue_node, "priority", :name),
          author: get_attribute_of_child_node(issue_node, "author", :name),
          project_id: get_attribute_of_child_node(issue_node, "project", :id).to_i,
          comments: get_comments_of_child_node(last_sync_date, issue_node)
          }
      }
    end

    # given an Ox xml node, find a child node by the specified child_node_name.  The specified node should
    #  have a single child node itself, which should contain a String.  This method returns that String.
    def get_value_of_text_child_node(node, child_node_name)
      node.locate(child_node_name)[0].nodes[0]
    end

    # prepends the issue description with a link to the issue on Redmine
    def get_issue_description(node)
      issue_id = get_value_of_text_child_node(node, "id")
      description = get_value_of_text_child_node(node, "description") || ""
      "#{@base_url}/issues/#{issue_id} \n\n#{description}"
    end

    # given an Ox xml node, find a child node by the specified child_node_name.  The specified node
    #  should have an attribute with the name specified by attr_name; this method returns the value
    #  of that attribute.
    def get_attribute_of_child_node(node, child_node_name, attr_name)
      node.locate(child_node_name)[0][attr_name]
    end

    def get_comments_of_child_node(last_sync_date, node)
      if last_sync_date
        comments = node.locate("journals")[0].nodes.collect do |comment|
          created_by = comment.locate("user")[0]["name"]
          created_on = comment.locate("created_on")[0].nodes[0]
          notes = comment.locate("notes")[0].nodes[0]
          {created_by: created_by, created_on: created_on, notes: notes}
        end
        comments.select { |comment| Time.parse(comment[:created_on]).to_i >= last_sync_date.to_i && comment[:notes] != nil} if comments
      end
    end
  end
end
