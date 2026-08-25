class PersonalFolderItem < ApplicationRecord
  belongs_to :personal_folder
  belongs_to :conversation
end
