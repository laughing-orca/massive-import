require 'webrick'
require 'cgi'

module MassiveImport
  class DashboardServer
    def start(**options)
      port = options.fetch(:dashboard_port, (ENV["dashboard_port"] || 9292).to_i)
      host = options.fetch(:dashboard_host, ENV["dashboard_host"] || "127.0.0.1")

      logger = WEBrick::Log.new($stdout, WEBrick::Log::INFO)
      server = WEBrick::HTTPServer.new(
        BindAddress: host,
        Port: port,
        Logger: logger,
        AccessLog: []
      )

      server.mount_proc('/') do |request, response|
        dispatch(request, response, logger) do
          home(request)
        end
      end

      server.mount_proc('/imports') do |request, response|
        dispatch(request, response, logger) do
          import(request)
        end
      end

      %w[INT TERM].each { |signal| trap(signal) { server.shutdown } }

      server.start
    end

    def dispatch(request, response, logger)
      unless request.request_method == 'GET'
        respond(response, 405, layout(request, 'Method not allowed', '<h1>405 Method Not Allowed</h1>'))
        return
      end

      title, content = yield

      if content
        respond(response, 200, layout(request, title, content))
      else
        respond(response, 404, layout(request, 'Not found', '<h1>404 Not Found</h1><p><a href="/">Back to imports</a></p>'))
      end
    rescue => e
      logger.info("Unhandled exception: message=#{e.message}")
      logger.info("Unhandled exception: trace=#{e.backtrace}")
      respond(response, 500, layout(request, 'Error', "<h1>500 Internal Server Error</h1><p><a href=\"/\">Back to imports</a></p>"))
    end

    def home(request)
      render_imports if request.path_info == '/'
    end

    def import(request)
      render_import($1.to_i) if request.path_info =~ %r{\A/(\d+)\z}
    end

    def respond(response, status, body)
      response.status = status
      response['Content-Type'] = 'text/html; charset=utf-8'
      response.body = body
    end

    def render_imports
      imports = Import.order(id: :desc).to_a
      return ['Imports', '<h1>Imports</h1><p>No imports found.</p>'] if imports.empty?

      headers = ['ID', 'Status', 'Processor', 'Attempt', 'Total', 'Batched', 'Concurrency', 'Batch size']
      rows = imports.map do |imp|
        [
          %(<a href="/imports/#{imp.id}">##{imp.id}</a>),
          h(imp.status),
          h(imp.processor_class),
          "#{imp.attempt} / #{imp.max_attempts}",
          imp.total_records,
          "#{imp.batch_records} / #{imp.total_records}",
          "#{imp.current_batch_concurrency} / #{imp.max_batch_concurrency}",
          imp.batch_size
        ]
      end

      ['Imports', "<h1>Imports</h1>#{table(headers, rows)}"]
    end

    def render_import(id)
      imp = Import.find_by(id: id)
      return ['Not found', '<h1>Import not found</h1><p><a href="/">Back to imports</a></p>'] unless imp

      batch_stats  = Batch.where(import_id: imp.id).group(:status).count
      record_stats = Record.where(import_id: imp.id).group(:status).count
      batches = Batch.where(import_id: imp.id).order(id: :desc).limit(100).to_a

      summary_headers = ['Processor', 'Attempt', 'Total records', 'Batched records', 'Concurrency', 'Batch size']
      summary_values = [
        h(imp.processor_class),
        "#{imp.attempt} / #{imp.max_attempts}",
        imp.total_records,
        "#{imp.batch_records} / #{imp.total_records}",
        "#{imp.current_batch_concurrency} / #{imp.max_batch_concurrency}",
        imp.batch_size
      ]

      content = +''
      content << %(<p><a href="/">&larr; All imports</a></p>)
      content << "<h1>Import ##{imp.id} (#{h(imp.status)})</h1>"
      content << table(summary_headers, [summary_values])

      content << '<h2>Batches by status</h2>'
      content << stats_table(batch_stats)
      content << '<h2>Records by status</h2>'
      content << stats_table(record_stats)
      content << '<h2>Recent 100 batches</h2>'
      content << batches_table(batches)

      ["Import ##{imp.id}", content]
    end

    def stats_table(stats)
      return '<p>None.</p>' if stats.empty?

      rows = stats.map { |status, count| [h(status), count] }
      rows << ['<strong>Total</strong>', "<strong>#{stats.values.sum}</strong>"]

      table(['Status', 'Count'], rows)
    end

    def batches_table(batches)
      return '<p>No batches yet.</p>' if batches.empty?

      rows = batches.map do |b|
        started = b.started_at ? Time.at(b.started_at.to_i).strftime('%Y-%m-%d %H:%M:%S') : '-'
        ["##{b.id}", b.attempt, h(b.status), b.start_id, b.end_id, started]
      end

      table(['Batch', 'Attempt', 'Status', 'Start ID', 'End ID', 'Started'], rows)
    end

    def table(headers, rows)
      head = headers.empty? ? '' : "<thead><tr>#{headers.map { |header| "<th>#{header}</th>" }.join}</tr></thead>"
      body = rows.map do |cells|
        "<tr>#{cells.map { |cell| "<td>#{cell}</td>" }.join}</tr>"
      end.join

      <<~TABLE
        <table border="1" cellpadding="4" cellspacing="0">
          #{head}
          <tbody>#{body}</tbody>
        </table>
      TABLE
    end

    def h(text)
      CGI.escapeHTML(text.to_s)
    end

    def layout(request, title, content)
      refresh = request.query['refresh'].to_i
      refresh_html = +''
      refresh_html << %(<meta http-equiv="refresh" content="#{refresh}">) if refresh > 0

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          #{refresh_html}
          <title>#{h(title)}</title>
        </head>
        <body>
          #{content}
        </body>
        </html>
      HTML
    end
  end
end
