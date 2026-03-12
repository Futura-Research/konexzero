class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages, id: :uuid do |t|
      t.references :application, type: :uuid, null: false, foreign_key: true
      t.string     :room_name,         null: false
      t.string     :sender_id
      t.string     :recipient_id
      t.string     :message_type,      null: false, default: "text"
      t.text       :content
      t.jsonb      :payload,           null: false, default: {}
      t.string     :client_message_id
      t.datetime   :sent_at,           null: false, default: -> { "NOW()" }
      t.datetime   :deleted_at

      t.timestamps
    end

    add_index :messages, [ :application_id, :room_name, :sent_at ]
    add_index :messages, [ :application_id, :recipient_id, :sent_at ]
    add_index :messages, [ :application_id, :client_message_id ],
              unique: true, where: "client_message_id IS NOT NULL"
    add_index :messages, :deleted_at
  end
end
