class AddSongNumber < ActiveRecord::Migration[4.2]
  def change
    add_column :songs, :song_number, :integer
  end
end
