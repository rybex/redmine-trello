module RMT
  class SynchronizationData
    attr_reader :id, :name, :description, :target_list_id, :color

    def initialize(id, name, description, color, comments, target_list_id, relevant_cards_loader)
      @id = id
      @name = name
      @description = description
      @target_list_id = target_list_id
      @color = color
      @comments = comments
      @relevant_cards_loader = relevant_cards_loader
    end

    def ensure_present_on(trello)
      card = get_card(trello)
      unless card
        insert_into(trello)
      else
        update_card(card)
      end
    end

    def is_data_for?(card)
      card.name.include? "##{@id}"
    end

  private

    def insert_into(trello)
      card = trello.create_card(:name => "##{@id} #{@name}",
                         :list => @target_list_id,
                         :description => @description,
                         :color => @color)
      update_card(card)
    end

    def update_card(card)
      if @comments
        @comments.each do |comment|
          puts "Updated card #{card.name}"
          text = "#{comment[:created_by]} wrote: \n\n#{comment[:notes]}"
          card.add_comment(text)
        end
      end
    end

    def get_card(trello)
      @relevant_cards_loader.call(trello).detect &method(:is_data_for?)
    end
  end
end
