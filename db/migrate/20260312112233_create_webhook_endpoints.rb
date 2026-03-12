class CreateWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints, id: :uuid do |t|
      t.references :application, type: :uuid, null: false, foreign_key: true
      t.string     :url,               null: false
      t.string     :secret,            null: false
      t.string     :description
      t.string     :subscribed_events, null: false, array: true, default: []
      t.boolean    :active,            null: false, default: true
      t.timestamps
    end

    add_index :webhook_endpoints, [ :application_id, :active ]
    add_index :webhook_endpoints, :url
  end
end
