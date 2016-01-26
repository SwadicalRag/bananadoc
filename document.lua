local doc = {}

function doc:newSandbox()
    local env = {banana = banana.Clone(banana)}
    env.banana.RootNamespace = {}
    return env,env.banana
end

function doc:sandboxRunCode(code,env,src)
    pcall(function()
        CompileString(code,src)
        debug.setfenv(code,env)
        code()
    end)
end

function doc:getLineFromString(str,line)
    local c_line,capturing = 0,line == 0
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

function doc:getFunctionCommentData(func,loc)
    local debugInfo = debug.getinfo(func)
    if debugInfo.short_src and debugInfo.linedefined then
        local fileContents = file.Read(func.short_src,loc)

        if fileContents then
            local comment,idx = {},1
            while true do
                local lineContents = self:getLineFromString(fileContents,debugInfo.linedefined-idx)
                if lineContents:sub(1,4) ~= " -- " then break end
                comment[idx] = lineContents
                idx = idx + 1
            end

            local commentData = {
                description = "",
                arguments = {}
            }

            if #comment > 0 then
                for i=1,#comment do
                    local commentStr = comment[#comment - i + 1]

                    if commentStr:match("^ -- @param%d+%s*.+$") then
                        local paramID,paramType,paramInfo = commentStr:match("^ -- @param(%d+)%s*(%S+)%s*(.*)$")
                        commentData[tonumber(paramID)] = {
                            type = paramType,
                            paramInfo = paramInfo
                        }
                    elseif commentStr:match("^ -- @desc%s*.+$") then
                        commentData.description = commentData.description..(commentStr:match("^ -- @desc%s*(.+)$"))
                    end
                end
            end

            if commentData.description == "" then
                commentData.description = "No description available."
            end

            if #commentData.arguments == 0 then
                commentData.arguments = false
            end

            return commentData
        end
    end
    return {
        description = "No description available.",
        arguments = false
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
    banana.forEachClass(function(class)
        for key,var in pairs(class) do
            if type(var) == "function" then
                local cdata = self:getFunctionCommentData(var,loc)
                table.insert(methods,{
                    name = class:GetInternalClassName().."->"..key,
                    description = cdata.description,
                    arguments = cdata.arguments
                })
            end
        end
    end)

    return util.TableToJSON(methods)
end

return doc
