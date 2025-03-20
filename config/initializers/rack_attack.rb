class Rack::Attack
  throttle("req/ip", limit: 100, period: 5.minutes) do |req|
    req.ip
  end

  throttle("logins/ip", limit: 5, period: 1.minute) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      req.ip
    end
  end

  throttle("search/ip", limit: 20, period: 1.minute) do |req|
    if req.path == "/api/v1/movies" && req.get?
      req.ip
    end
  end

  blocklist("block suspicious agents") do |req|
    req.user_agent =~ /^(curl|wget|nmap|nikto|sqlmap|libwww-perl)/i
  end

  self.throttled_response = lambda do |env|
    [
      429,  # status
      { "Content-Type" => "application/json" },
      [ { error: "Rate limit exceeded. Please try again later." }.to_json ]
    ]
  end
end
