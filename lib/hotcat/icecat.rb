# ICEcat constants
class Icecat

  class << self; attr_accessor :fallback_language_id, :english_language_id end

  # This is the language ID to fallback to if there is no English entry.
  self.fallback_language_id = "1"

  # The ID for English.
  self.english_language_id = "9"

end