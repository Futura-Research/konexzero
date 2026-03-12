class CreateRooms < ActiveRecord::Migration[8.1]
  def change
    create_table :rooms, id: :uuid do |t|
      t.references :application, null: false, foreign_key: true, type: :uuid
      t.string :room_id, null: false
      t.string :display_name, null: false
      t.integer :status, null: false, default: 0
      t.integer :max_participants
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :rooms, :room_id, unique: true
    add_index :rooms, %i[application_id status]
    add_index :rooms, %i[application_id created_at]
    add_index :rooms, %i[status ended_at]
  end
end
