local doc = {}

function doc:newSandbox()
    local env = {banana = banana.Clone(banana)}
    env.banana.RootNamespace = {}
    return env,env.banana
end

function doc:sandboxRunCode(code,env,src)
    pcall(function()
        local fn = CompileString(code,src)
        debug.setfenv(fn,env)
        fn(env)
    end)
end

function doc:getLineFromString(str,line)
    local c_line,capturing = 1,line == 1
    local out = ""
    for char in str:gmatch("(.)") do
        if char == "\n" then
            if capturing then
                if out:sub(-1,-1) == "\r" then out = out:sub(1,-2) end
                return out
            else
                c_line = c_line + 1

                if c_line == line then
                    capturing = true
                end
            end
        elseif capturing then
            out = out..char
        end
    end

    return (str:match("[^\r\n]+$")) or ""
end

function doc:getFileData(func,loc)
    local debugInfo = debug.getinfo(func)
    if debugInfo.short_src then
        local fileContents = file.Read(debugInfo.short_src,loc)

        if fileContents then
            local comment,idx = {},1
            while true do
                local lineContents = self:getLineFromString(fileContents,idx)
                if lineContents:sub(1,3) ~= "-- " then break end
                comment[#comment+1] = lineContents
                idx = idx + 1
            end

            local fileData = {
                purpose = "",
                author = "",
                name = "",
                state = 3
            }

            if #comment > 0 then
                for i=1,#comment do
                    local commentStr = comment[i]
                    if commentStr:match("-- @author .+") then
                        fileData.author = commentStr:match("-- @author (.+)")
                    elseif commentStr:match("-- @purpose .+") then
                        fileData.purpose = fileData.purpose..(commentStr:match("-- @purpose (.+)"))
                    elseif commentStr:match("-- @name .+") then
                        fileData.name = commentStr:match("-- @name (.+)")
                    elseif commentStr:match("-- @state .+") then
                        local state = commentStr:match("-- @state (.+)")
                        if state == "SERVER" then
                            fileData.state = 0
                        elseif state == "CLIENT" then
                            fileData.state = 1
                        elseif state == "SHARED" then
                            fileData.state = 2
                        end
                    end
                end

                if fileData.purpose == "" then fileData.purpose = "Unknown." end
                if fileData.author == "" then fileData.author = "Unknown." end
                if fileData.name == "" then fileData.name = "Unknown." end

                return fileData
            end
        end
    end

    return {
        purpose = "Unknown.",
        author = "Unknown.",
        name = "Unknown.",
        state = 3
    }
end

function doc:getFunctionCommentData(func,loc)
    local debugInfo = debug.getinfo(func)
    if debugInfo.short_src and debugInfo.linedefined then
        local fileContents = file.Read(debugInfo.short_src,loc)

        if fileContents then
            local comment,idx = {},1
            while true do
                local lineContents = self:getLineFromString(fileContents,debugInfo.linedefined-idx)
                if lineContents:sub(1,3) ~= "-- " then break end
                comment[idx] = lineContents
                idx = idx + 1
            end

            local commentData = {
                description = "",
                arguments = {},
                returns = {}
            }

            if #comment > 0 then
                for i=1,#comment do
                    local commentStr = comment[#comment - i + 1]

                    if commentStr:match("^-- @param%d+%s*.+$") then
                        local paramID,paramType,paramInfo = commentStr:match("^-- @param(%d+)%s*(%S+)%s*(.*)$")
                        commentData.arguments[tonumber(paramID)] = {
                            type = paramType,
                            paramInfo = paramInfo
                        }
                    elseif commentStr:match("^-- @return%d+%s*.+$") then
                        local paramID,paramType,paramInfo = commentStr:match("^-- @return(%d+)%s*(%S+)%s*(.*)$")
                        commentData.returns[tonumber(paramID)] = {
                            type = paramType,
                            paramInfo = paramInfo
                        }
                    elseif commentStr:match("^-- @desc%s*.+$") then
                        commentData.description = commentData.description..(commentStr:match("^-- @desc%s*(.+)$")).."\n"
                    end
                end
            end

            if commentData.description == "" then
                commentData.description = "No description available."
            else
                commentData.description = commentData.description:sub(1,-2)
            end

            if #commentData.arguments == 0 then
                commentData.arguments = false
            end

            if #commentData.returns == 0 then
                commentData.returns = false
            end

            return commentData
        end
    end
    return {
        description = "No description available.",
        arguments = false,
        returns = false
    }
end

function doc:DocumentFolder(path,loc)
    local env,banana = self:newSandbox()

    local function recurseFolder(path,loc) -- ends with /
        local files,folders = file.Find(path.."*",loc)

        for _,fileName in ipairs(files) do
            if fileName:sub(-4,-1) == ".lua" then
                self:sandboxRunCode(file.Read(path..fileName,loc),env,path..fileName)
            end
        end

        for _,folderName in ipairs(folders) do
            recurseFolder(path..folderName.."/",loc)
        end
    end

    recurseFolder(path,loc)

    local methods = {}
    local seenClasses = {}
    local classes = {}
    banana.forEachClass(function(class)
        for key,var in pairs(class) do
            if type(var) == "function" then
                if not (banana.IgnoreKeys[key] or banana.Protected[key]) then
                    if not seenClasses[class:GetInternalClassName()] then
                        local fdata = self:getFileData(var,loc)
                        fdata.class = class:GetInternalClassName()
                        table.insert(classes,fdata)
                        seenClasses[class:GetInternalClassName()] = true
                    end

                    local cdata = self:getFunctionCommentData(var,loc)
                    table.insert(methods,{
                        name = class:GetInternalClassName().."->"..key,
                        description = cdata.description,
                        arguments = cdata.arguments,
                        returns = cdata.returns,
                        class = class:GetInternalClassName()
                    })
                end
            end
        end
    end)

    return methods,classes
end

return doc
