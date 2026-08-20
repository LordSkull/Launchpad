class DropUsers < ActiveRecord::Migration[6.1]
  def up
    drop_table :users
  end

  def down
    create_table :users, id: :integer do |t|
      t.string :username
      t.string :password_digest
      t.timestamps null: false
    end
  end
end
