
class Assignments
  def nested_assignment
    @email ||= if (email = ::ScoutApm::AutoInstrument("session[\"email\"]",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:4:in `nested_assignment'"]){session["email"]}).present?
        ::ScoutApm::AutoInstrument("User.where(email: email).first",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:5:in `nested_assignment'"]){User.where(email: email).first}
      else
        nil
      end
  end

  def paginate_collection(coll)
    page = (::ScoutApm::AutoInstrument("params[:page].present?",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:12:in `paginate_collection'"]){params[:page].present?} ? ::ScoutApm::AutoInstrument("params[:page].to_i",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:12:in `paginate_collection'"]){params[:page].to_i} : 1)
    per_page = (::ScoutApm::AutoInstrument("params[:per_page].present?",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:13:in `paginate_collection'"]){params[:per_page].present?} ? ::ScoutApm::AutoInstrument("params[:per_page].to_i",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:13:in `paginate_collection'"]){params[:per_page].to_i} : 20)
    pagination, self.collection = ::ScoutApm::AutoInstrument("pagy(...",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:14:in `paginate_collection'"]){pagy(
      coll,
      items: per_page,
      page: page
    )}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_TOTAL_HEADER] = pagination.count.to_s",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:19:in `paginate_collection'"]){headers[PAGINATION_TOTAL_HEADER] = pagination.count.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_TOTAL_PAGES_HEADER] = pagination.pages.to_s",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:20:in `paginate_collection'"]){headers[PAGINATION_TOTAL_PAGES_HEADER] = pagination.pages.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_PER_PAGE_HEADER] = per_page.to_s",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:21:in `paginate_collection'"]){headers[PAGINATION_PER_PAGE_HEADER] = per_page.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_PAGE_HEADER] = pagination.page.to_s",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:22:in `paginate_collection'"]){headers[PAGINATION_PAGE_HEADER] = pagination.page.to_s}
    ::ScoutApm::AutoInstrument("headers[PAGINATION_NEXT_PAGE_HEADER] = pagination.next.to_s",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:23:in `paginate_collection'"]){headers[PAGINATION_NEXT_PAGE_HEADER] = pagination.next.to_s}
    ::ScoutApm::AutoInstrument("collection",["/home/samuel/Documents/scoutapp/scout_apm_ruby/test/unit/auto_instrument/assignments.rb:24:in `paginate_collection'"]){collection}
  end
end
