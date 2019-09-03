
class Assignments
  def nested_assignment
    @email ||= if (email = session["email"]).present?
        User.where(email: email).first
      else
        nil
      end
  end
end
