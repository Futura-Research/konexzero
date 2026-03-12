class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_events, id: :uuid do |t|
      t.references :webhook_endpoint, type: :uuid, null: false, foreign_key: true
      t.string     :event_type,       null: false
      t.jsonb      :payload,          null: false, default: {}
      t.string     :status,           null: false, default: "pending"
      t.integer    :response_code
      t.text       :response_body
      t.integer    :attempts,         null: false, default: 0
      t.datetime   :last_attempted_at
      t.datetime   :delivered_at
      t.timestamps
    end

    add_index :webhook_events, [ :webhook_endpoint_id, :status ]
    add_index :webhook_events, [ :webhook_endpoint_id, :created_at ]
    add_index :webhook_events, [ :status, :last_attempted_at ]
  end
end
