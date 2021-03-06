module UniversalTracker
  class App < Sinatra::Base
    def process_done(request, data)
      downloader = data["downloader"]
      item = data["item"]
      bytes = data["bytes"]

      if downloader.is_a?(String) and
         item.is_a?(String) and
         bytes.is_a?(Hash) and
         bytes.all?{|k,v|k.is_a?(String) and v.is_a?(Integer)}

        done_hash = { "item"=>item,
                      "by"=>downloader,
                      "ip"=>request.ip,
                      "ua"=>request.user_agent,
                      "at"=>Time.now.utc.xmlschema,
                      "bytes"=>bytes }
        if data["version"].is_a?(String)
          done_hash["version"] = data["version"]
        end
        if data["id"]
          done_hash["id"] = data["id"]
        end

        if bytes.keys.sort != tracker_config.domains.keys.sort
          p "Hey, strange data: #{ done_hash.inspect }"
          tracker.block_ip(request.ip, done_hash)
          tracker.release_item(item)
          "OK\n"
        else
          if tracker.mark_item_done(downloader, item, bytes, done_hash)
            "OK\n"
          else
            "Invalid item."
          end
        end
      else
        raise "Invalid input: #{ data.inspect }."
      end
    end

    def process_request(request, data)
      downloader = data["downloader"]
      version = data["version"]

      if not tracker.check_version(version)
        status 455
        ""
      elsif downloader.is_a?(String)
        case tracker.check_not_blocked_and_request_rate_ok(request.ip, downloader)
        when :blocked
# TODO logging
#         p "Hey, blocked: #{ request.ip }"
          raise Sinatra::NotFound
        when :rate_limit
          status 429
          ""
        else
          tracker.request_item(request.ip, downloader) or raise Sinatra::NotFound
        end
      else
        raise "Invalid input."
      end
    end

    def process_uploaded(request, data)
      uploader = data["uploader"]
      item = data["item"] || data["user"]
      server = data["server"]

      if uploader.is_a?(String) and
         item.is_a?(String) and
         server.is_a?(String)
        tracker.log_upload(request.ip, uploader, item, server)
        "OK\n"
      else
        raise "Invalid input."
      end
    end


    post "/:slug/request" do
      process_request(request, JSON.parse(request.body.read))
    end

    post "/:slug/release" do
      content_type :text
      data = JSON.parse(request.body.read)
      if tracker.release_item(data["item"])
        "Released OK.\n"
      else
        "Invalid item.\n"
      end
    end

    post "/:slug/done" do
      content_type :text
      process_done(request, JSON.parse(request.body.read))
    end

    post "/:slug/done+request" do
      content_type :text
      data = JSON.parse(request.body.read)
      process_done(request, data)
      process_request(request, data)
    end

    get "/:slug/items/:item.json" do |item|
      content_type :json
      data = {
        :status=>tracker.item_status(item)
      }
      if data[:status]==:out
        data[:downloader] = tracker.item_claimant(item)
      end
      JSON.dump(data)
    end

    post "/:slug/uploaded" do
      content_type :text
      process_uploaded(request, JSON.parse(request.body.read))
    end

    post "/:slug/upload" do
      data = JSON.parse(request.body.read)
      downloader = data["downloader"]

      content_type :json
      if downloader.is_a?(String) and target = tracker.random_upload_target
        JSON.dump(:upload_target=>target.gsub(":downloader", downloader))
      else
        "{}"
      end
    end
  end
end

