class CreateChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :channels do |t|
      t.string :user_id, null: false
      t.string :name
      t.string :arn, null: false
      t.string :ingest_endpoint, null: false
      t.string :playback_url, null: false
      t.string :stream_key_arn
      t.string :stream_key_value, null: false
      t.string :ivs_channel_type, null: false, default: "STANDARD"
      t.boolean :authorized, null: false, default: false

      t.timestamps
    end
    add_index :channels, :user_id
    add_index :channels, :arn, unique: true
  end
end
