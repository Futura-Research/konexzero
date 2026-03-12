class CreateApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :applications, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.jsonb :metadata, null: false, default: {}
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :applications, :slug, unique: true
    add_index :applications, :discarded_at
  end
end
