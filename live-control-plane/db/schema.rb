# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_03_114838) do
  create_table "channels", force: :cascade do |t|
    t.string "arn", null: false
    t.boolean "authorized", default: false, null: false
    t.datetime "created_at", null: false
    t.string "ingest_endpoint", null: false
    t.string "ivs_channel_type", default: "STANDARD", null: false
    t.string "name"
    t.string "playback_url", null: false
    t.string "stream_key_arn"
    t.string "stream_key_value", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.index ["arn"], name: "index_channels_on_arn", unique: true
    t.index ["user_id"], name: "index_channels_on_user_id"
  end
end
