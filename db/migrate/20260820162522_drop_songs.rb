class DropSongs < ActiveRecord::Migration[6.1]
  def up
    drop_table :songs
  end

  def down
    create_table :songs, id: :integer do |t|
      t.text :song_data
      t.timestamps null: false, precision: nil
      t.string :name
      t.integer :song_number
    end
  end
end
