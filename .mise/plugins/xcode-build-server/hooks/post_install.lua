function PLUGIN:PostInstall(ctx)
    local installDir = ctx.rootPath
    local binDir = installDir .. "/bin"

    os.execute("mkdir -p " .. binDir)
    os.execute("chmod +x " .. installDir .. "/xcode-build-server")
    os.execute("ln -sf " .. installDir .. "/xcode-build-server " .. binDir .. "/xcode-build-server")
end
