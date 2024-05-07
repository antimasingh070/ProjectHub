class CreateLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :logs do |t|
      t.references :user, foreign_key: true
      t.string :action
      t.references :issue, foreign_key: true
      t.references :project, foreign_key: true
      t.timestamp :timestamp

      # Add more fields as needed

      t.timestamps
    end
  end
end
