class SearchUpdatesChannel < ApplicationCable::Channel
  def subscribed
    # ActionCable.server.broadcast("search_updates_#{user.id}", { message: "New search results available." })
    stream_from "search_updates_#{current_user.id}"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
