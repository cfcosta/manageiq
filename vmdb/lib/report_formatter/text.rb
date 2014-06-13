module ReportFormatter
  class ReportText < Ruport::Formatter
    renders :text, :for => ReportRenderer

    # determines the text widths for each column.
    def calculate_max_col_widths
      mri = options.mri
      # allow override
      #     return if max_col_width
      tz = mri.get_time_zone(Time.zone.name)

      @max_col_width=Array.new
      unless mri.headers.empty?
        mri.headers.each_index do |i|
          @max_col_width[i] = mri.headers[i].to_s.length
        end
      end
      mri.table.data.each { |r|
        mri.col_formats ||= Array.new                 # Backward compat - create empty array for formats
        mri.col_order.each_with_index do |f,i|
          unless ["<compare>","<drift>"].include?(mri.db)
            data = mri.format(f,
                              r[f],
                              :format=>mri.col_formats[i] ? mri.col_formats[i] : :_default_,
                              :tz=>tz)
          else
            data = r[f].to_s
          end
          if !@max_col_width[i] || data.length > @max_col_width[i]
            @max_col_width[i] = data.length
          end
        end
      }
    end

    # method to get friendly values for company tag and user filters
    def calculate_filter_names(tag)
      categories = Classification.categories.collect {|c| c unless !c.show}.compact
      tag_val = ""
      categories.each do |category|
        entries = Hash.new
        category.entries.each do |entry|
          entries[entry.description] = entry.tag.name # Get the fully qual tag name
          if tag == entry.tag.name
            tag_val = "#{category.description}: #{entry.description}"
          end
        end
      end
      return tag_val
    end

    # Uses the column names from the given Data::Table to generate a table
    # header.
    #
    # calls fit_to_width to truncate table heading if necessary.
    def build_document_header
      mri = options.mri
      raise "No settings configured for Table" if mri.table.nil?
      calculate_max_col_widths
      @hr = hr

      if mri.title!=nil # generate title line, if present
        output << @hr
        temp_title = mri.title
        temp_title << " (" << mri.report_run_time.to_s << ")" if !mri.report_run_time.nil?
        t = temp_title.center(@line_len-2)
        output << fit_to_width("|#{t}|" + CRLF)
        if !mri.db.nil? && mri.db == "<drift>"
          t2 = "(* = Value changed from previous column)"
          t2 = t2.center(@line_len-2)
          output << fit_to_width("|#{t2}|" + CRLF)
        end
      end

      return if mri.headers.empty?
      c = mri.headers.dup
      c.each_with_index { |f,i|
        c[i] = f.to_s.center(@max_col_width[i])
      }
      output << fit_to_width("#{@hr}| #{Array(c).join(' | ')} |" + CRLF)
    end

    # Generates the body of the text table.
    #
    # Defaults to numeric values being right justified, and other values being
    # left justified.  Can be changed to support centering of output by
    # setting alignment to :center
    #
    # Uses fit_to_width to truncate table if necessary
    def build_document_body
      mri = options.mri
      tz = mri.get_time_zone(Time.zone.name)
      s = @hr

      save_val = nil
      counter = 0

      cfg = VMDB::Config.new("vmdb").config[:reporting]       # Read in the reporting column precisions
      default_precision = cfg[:precision][:default]           # Set the default
      precision_by_column = cfg[:precision_by_column]         # get the column overrides
      precisions = {}                                         # Hash to store columns we hit

      row_limit = mri.rpt_options && mri.rpt_options[:row_limit] ? mri.rpt_options[:row_limit] : 0
      use_table = mri.sub_table ? mri.sub_table : mri.table
      use_table.data.each_with_index { |r,d_idx|
        break if row_limit != 0 && d_idx > row_limit - 1
        line = Array.new
        line_wrapper = false        # Clear line wrapper flag
        if ["<compare>"].include?(mri.db) && r[0] == "% Match:"
          line_wrapper = true       # Wrap compare % lines with header rows
        elsif ["<drift>"].include?(mri.db) && r[0] == "Changed:"
          line_wrapper = true       # Wrap drift changed lines with header rows
        end
        mri.col_formats ||= Array.new                 # Backward compat - create empty array for formats
        mri.col_order.each_with_index do |f,i|
          unless ["<compare>","<drift>"].include?(mri.db)
            data = mri.format(f,
                              r[f],
                              :format=>mri.col_formats[i] ? mri.col_formats[i] : :_default_,
                              :tz=>tz)
          else
            data = r[f].to_s
          end
          if options.alignment.eql? :center
            line << data.center(@max_col_width[i])
          else
            align = data.is_a?(Numeric) ? :rjust : :ljust
            line << data.send(align, @max_col_width[i])
          end
        end

        # generate a break line if grouping is turned on
        if ["y","c"].include?(mri.group) && mri.sortby != nil
          if d_idx > 0 && save_val != r[mri.sortby[0]]
            if mri.group == "c"
              s += @hr
              t = " Total for #{save_val}: #{counter} ".center(@line_len-2)
              s += fit_to_width("|#{t}|" + CRLF)
              s += @hr
              counter = 0
            else
              s += @hr
            end
          end
          save_val = r[mri.sortby[0]]
          counter += 1
        end
        s += @hr if line_wrapper
        s += "| #{line.join(' | ')} |" + CRLF
        s += @hr if line_wrapper
      }

      # see if a final group line needs to be written
      if ["y","c"].include?(mri.group) && mri.sortby != nil
        if mri.group == "c"
          s += @hr
          t = " Total for #{save_val}: #{counter} ".center(@line_len-2)
          s += fit_to_width("|#{t}|" + CRLF)
        end
      end

      s += @hr
      output << fit_to_width(s)
    end

    def build_document_footer
      mri = options.mri
      tz = mri.get_time_zone(Time.zone.name)
      if ! mri.user_categories.blank? || ! mri.categories.blank? || ! mri.conditions.nil? || ! mri.display_filter.nil?
        output << @hr
        if ! mri.user_categories.blank?
          user_filters = mri.user_categories.flatten
          if ! user_filters.blank?
            customer_name = VMDB::Config.new("vmdb").config[:server][:company]
            user_filter = "User assigned " + customer_name + " Tag filters:"
            t = user_filter + " " *(@line_len-2-user_filter.length)
            output << fit_to_width("|#{t}|" + CRLF)
            user_filters.each do | filters |
              tag_val = "  " + calculate_filter_names(filters)
              tag_val1 = tag_val + " " *(@line_len-tag_val.length-2)
              output << fit_to_width("|#{tag_val1}|" + CRLF)
            end
          end
        end

        if ! mri.categories.blank?
          categories = mri.categories.flatten
          if ! categories.blank?
            customer_name = VMDB::Config.new("vmdb").config[:server][:company]
            customer_name_title = "Report based " + customer_name + " Tag filters:"
            t = customer_name_title + " " *(@line_len-customer_name_title.length-2)
            output << fit_to_width("|#{t}|" + CRLF)
            categories.each do | filters |
              tag_val = "  " + calculate_filter_names(filters)
              tag_val1 = tag_val + " " *(@line_len-tag_val.length-2)
              output << fit_to_width("|#{tag_val1}|" + CRLF)
            end
          end
        end

        if ! mri.conditions.nil?
          if mri.conditions.is_a?(Hash)
            filter_fields = "Report based filter fields:"
            t = filter_fields + " " *(@line_len-2-filter_fields.length)
            output << fit_to_width("|#{t}|" + CRLF)

            # Clean up the conditions for display
            tables = mri.conditions[:field].split("-")[0].split(".")  # Get the model and tables
            field = Dictionary::gettext(tables[0], :type=>:model, :notfound=>:titleize) # Start with the model
            tables[1..-1].each do |t| # Add on any tables
              field += "." + Dictionary::gettext(t, :type=>:table, :notfound=>:titleize)
            end
            # Add on the column name
            field += " : " + Dictionary::gettext(mri.conditions[:field].split("-")[1], :type=>:column, :notfound=>:titleize)

            filter_val = "  " + field +  " " + mri.conditions[:operator] + " " + mri.conditions[:string].to_s
            t = filter_val + " " *(@line_len-filter_val.length-2)
            output << fit_to_width("|#{t}|" + CRLF)
          else
            filter_fields = "Report based filter fields:"
            t = filter_fields + " " *(@line_len-2-filter_fields.length)
            output << fit_to_width("|#{t}|" + CRLF)
            filter_val = mri.conditions.to_human
            t = filter_val + " " *(@line_len-filter_val.length-2)
            output << fit_to_width("|#{t}|" + CRLF)
          end
        end

        if ! mri.display_filter.nil?
          filter_fields = "Display Filter:"
          t = filter_fields + " " *(@line_len-2-filter_fields.length)
          output << fit_to_width("|#{t}|" + CRLF)
          filter_val = mri.display_filter.to_human
          t = filter_val + " " *(@line_len-filter_val.length-2)
          output << fit_to_width("|#{t}|" + CRLF)
        end
      end

      output << @hr
      cr = format_timezone(Time.now, tz).to_s # Label footer with current time in selected time zone
      f = cr.center(@line_len-2)
      output << fit_to_width("|#{f}|" + CRLF)
      output << @hr


    end

    # Generates the horizontal rule by calculating the total table width and
    # then generating a bar that looks like this:
    #
    #   "+------------------+"
    def hr
      mri = options.mri
      if mri.table.column_names.include?("id")  # Use 1 less column if "id" is present
        @line_len = @max_col_width.inject((mri.table.data[0].to_miq_a.length-1) * 3) {|s,e|s+e}+1
        "+" + "-"*(@line_len-2) + "+" + CRLF
      else
        @line_len = @max_col_width.inject((mri.table.data[0].to_miq_a.length) * 3) {|s,e|s+e}+1
        "+" + "-"*(@line_len-2) + "+" + CRLF
      end
    end

    # Returns table_width if specified.
    #
    # Otherwise, uses SystemExtensions to determine terminal width.
    def width
      options.table_width || @line_len
    end

    # Truncates a string so that it does not exceed Text#width
    def fit_to_width(s)
      # workaround for Rails setting terminal_width to 1
      width < 2 ? max_width = @line_len : max_width = width

      s.split(CRLF).each { |r|
        r.gsub!(/\A.{#{max_width+1},}/) { |m| m[0,max_width-2] + ">>" }
      }.join(CRLF) + CRLF
    end
  end
end
