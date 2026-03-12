class CreateWebrtcCallEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webrtc_call_events, id: :uuid do |t|
      t.references :application, type: :uuid, null: false, foreign_key: true
      t.string     :event_type,    null: false
      t.string     :room_name,     null: false
      t.string     :participant_id
      t.jsonb      :payload,       null: false, default: {}
      t.datetime   :occurred_at,   null: false, default: -> { "NOW()" }

      t.timestamps
    end

    add_index :webrtc_call_events, [ :application_id, :event_type, :occurred_at ]
    add_index :webrtc_call_events, [ :application_id, :room_name, :occurred_at ]
  end
end
