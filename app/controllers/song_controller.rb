class SongController < ApplicationController
  def view_all
    render :json => {"data" => Song.where("cast(song_number as text) LIKE ?", "%#{params[:songNum]}%")}
  end
end
