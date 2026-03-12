class CreateApiCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :api_credentials, id: :uuid do |t|
      t.references :application, null: false, foreign_key: true, type: :uuid
      t.string :app_id, null: false
      t.string :secret_key_digest, null: false
      t.string :secret_key_prefix, null: false
      t.string :label
      t.boolean :active, null: false, default: true
      t.datetime :last_used_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :api_credentials, :app_id, unique: true
    add_index :api_credentials, %i[app_id active]
  end
end
