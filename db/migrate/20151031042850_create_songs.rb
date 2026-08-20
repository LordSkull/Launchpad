class CreateSongs < ActiveRecord::Migration[4.2]
  def change
    create_table :songs do |t|
      t.text :song_data

      t.timestamps null: false
    end
  end
end
