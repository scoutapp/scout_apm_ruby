
class Assignments
  def nested_assignment
    @email ||= if (email = ::ScoutApm::AutoInstrument("session[\"email\"]",["BACKTRACE"]){session["email"]}).present?
        ::ScoutApm::AutoInstrument("User.where(email: email).first",["BACKTRACE"]){User.where(email: email).first}
      else
        nil
      end
  end

  def paginate_collection(coll)
    page = (::ScoutApm::AutoInstrument("params[:page].present?",["BACKTRACE"]){params[:page].to_i} : 1)
    per_page = (::ScoutApm::AutoInstrument("params[:per_page].present?",["BACKTRACE"]){params[:per_page].to_i} : 20)
    pagination, self.collection = ::ScoutApm::AutoInstrument("pagy(...",["BACKTRACE"]){pagy(
      coll,
      items: per_page,
      page: page
    )}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_TOTAL_HEADER] = pagination.count.to_s",["BACKTRACE"]){headers[PAGINATION_TOTAL_HEADER] = pagination.count.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_TOTAL_PAGES_HEADER] = pagination.pages.to_s",["BACKTRACE"]){headers[PAGINATION_TOTAL_PAGES_HEADER] = pagination.pages.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_PER_PAGE_HEADER] = per_page.to_s",["BACKTRACE"]){headers[PAGINATION_PER_PAGE_HEADER] = per_page.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_PAGE_HEADER] = pagination.page.to_s",["BACKTRACE"]){headers[PAGINATION_PAGE_HEADER] = pagination.page.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_NEXT_PAGE_HEADER] = pagination.next.to_s",["BACKTRACE"]){headers[PAGINATION_NEXT_PAGE_HEADER] = pagination.next.to_s}
    ::ScoutApm::AutoInstrument("collection",["BACKTRACE"]){collection}
  end
end
