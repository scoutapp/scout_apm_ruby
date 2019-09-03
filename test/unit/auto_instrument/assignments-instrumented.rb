
class Assignments
  def nested_assignment
    @email ||= if (email = ::ScoutApm::AutoInstrument("session[\"email\"]",["BACKTRACE"]){session["email"]}).present?
        ::ScoutApm::AutoInstrument("User.where(email: email).first",["BACKTRACE"]){User.where(email: email).first}
      else
        nil
      end
  end
end
