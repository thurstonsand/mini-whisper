function PLUGIN:PreInstall(ctx)
    local version = ctx.version

    local url = "https://github.com/SolaWing/xcode-build-server/archive/refs/tags/v" .. version .. ".tar.gz"

    return {
        version = version,
        url = url,
    }
end
