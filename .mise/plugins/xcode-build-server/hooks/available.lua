function PLUGIN:Available(ctx)
    local http = require("http")
    local json = require("json")

    local resp, err = http.get({
        url = "https://api.github.com/repos/SolaWing/xcode-build-server/tags",
    })

    if err ~= nil then
        error("Failed to fetch versions: " .. err)
    end
    if resp.status_code ~= 200 then
        error("GitHub API returned status " .. resp.status_code)
    end

    local tags = json.decode(resp.body)
    local result = {}

    for _, tag_info in ipairs(tags) do
        local version = tag_info.name:gsub("^v", "")
        table.insert(result, { version = version })
    end

    return result
end
