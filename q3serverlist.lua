--------------------------------------------------
-- Simple Quake 3 Server Lister
-- Author: Dion Williams
-- Copyright: 2012 Dion Williams
-- Licence: MIT/X11; Please see bottom of file
-- Requires: LuaSocket
--------------------------------------------------

-- Load Libraries
local socket = require("socket")

-- Connection parameters
local hostname -- Hostname of the master server to query
local port     -- Port of the master server to query
local protocol -- Protocol number to use for the request
local params   -- Extra parameters to send to the master server

local client      -- The socket
local destination -- Resolved IP address of the master server

-- Print helpful usage information
function printUsage()
  io.write("Retrieves and displays a list of servers from a Quake III Arena compatible\n")
  io.write("master server.\n")
  io.write("\n")
  io.write("Usage: q3serverlist <hostname> <port> <protocol> [params...]\n")
  io.write("\n")
  io.write("  hostname    Hostname of the master server to query.\n")
  io.write("  port        Port of the master server to query.\n")
  io.write("  protocol    Protocol number to use for the request.\n")
  io.write("  params      Extra parameters to send to the master server.\n")
  io.write("\n")
  io.write("Example: q3serverlist masterjk3.ravensoft.com 29060 26\n")
  io.write("         Retrieves all the Jedi Academy 1.01 servers from Ravensoft's official\n")
  io.write("         master server.\n")
  io.write("\n")
end

-- Helper function to check whether the string 'str' starts with 'substr'
function startsWith(str,substr)
   return string.sub(str, 1, string.len(substr)) == substr
end

-- Return the key/value pairs of an Info String as a table
function infoStringToTable(text)
  local i = 1
  local t = {}
  while true do
    -- Seek to the first backslash
    i = text:find("\\", i)
    -- If end is reached, return the table
    if i == nil then
      return t
    end
    -- Read in this key
    local key = text:match("^\\[^\\]*", i)
    if key ~= nil then
      i = i + key:len()
      -- Strip the preceding backslash
      key = key:sub(2)

      -- Now read the value for this key
      local value = text:match("^\\[^\\]*", i)
      if value ~= nil then
        i = i + value:len()
        -- Strip the preceding backslash
        value = value:sub(2)
        -- Add it into the table
        t[key] = value
      else
        -- Malformed sequence, return nil
        return nil
      end
    else
      -- Malformed sequence, return nil
      return nil
    end
  end
end

-- Print out the information of a server
function printServer(server)
  -- Length of each column's available character space
  local len1, len2, len3, len4 = 39, 19, 9, 9

  local svhostname = string.sub(server["hostname"] or "N/A", 1, len1)
  local svmapname  = string.sub(server["mapname"]  or "N/A", 1, len2)
  local svclients = "N/A"
  if server["clients"] and server["sv_maxclients"] then
    svclients  = string.sub(server["clients"] .. "/" .. server["sv_maxclients"], 1, len3)
  end
  local svgametype = string.sub(server["gametype"] or "N/A", 1, len4)

  io.write(svhostname)
  for i=1,len1-svhostname:len() do io.write(" ") end
  io.write(" ")

  io.write(svmapname)
  for i=1,len2-svmapname:len() do io.write(" ") end
  io.write(" ")

  io.write(svclients)
  for i=1,len3-svclients:len() do io.write(" ") end
  io.write(" ")

  io.write(svgametype)
  for i=1,len4-svgametype:len() do io.write(" ") end
  io.write("\n")
end

-- Handle an incoming getserversResponse packet from the master server
function incomingGetServersResponse(msg, fromaddr, fromport)
  if fromaddr ~= destination or fromport ~= port then
    return
  end

  -- Find first token
  local pos = string.find(msg, "\\", 1, true)
  if pos == nil then
    return
  end

  msg = msg:sub(pos)

  -- Parse all the servers
  for i=1,msg:len()-6,7 do
    if msg:sub(i,i) ~= "\\" then
      break
    end

    local o1,o2,o3,o4,highport,lowport = string.byte(msg, i+1, i+6)
    if o1 and o2 and o3 and o4 and highport and lowport then
      local svaddr = o1 .. "." .. o2 .. "." .. o3 .. "." .. o4
      local svport = highport*256 + lowport
      --io.write("Sending getinfo request to " .. svaddr .. ":" .. svport .. "\n")
      assert( client:sendto("\255\255\255\255getinfo xxx", svaddr, svport) ) -- Send the request
    else
      break
    end
  end
end

-- Handle an incoming infoResponse packet from a game server
function incomingInfoResponse(msg, fromaddr, fromport)
  local infotable = infoStringToTable(msg)
  if infotable ~= nil then
    printServer(infotable)
  end
end

-- The start of the program
function main()
  io.write("\n")

  -- Ensure at least the hostname, port, and protocol is given
  if #arg < 3 then
    printUsage()
    return 0
  end

  -- Parse hostname
  hostname = arg[1]

  -- Parse port
  port = tonumber(arg[2])
  if port == nil or port < 1 or port > 65535 then
    io.write("The port number must be between 1 and 65535.\n")
    return 1
  end

  -- Parse protocol
  protocol = tonumber(arg[3])
  if protocol == nil or protocol <= 0 then
    io.write("The protocol number must be a positive integer.\n")
    return 1
  end

  -- Parse any parameters for the master server
  params = {}
  for i=4,#arg do
    if string.find(arg[i], "%s") == nil then
      table.insert(params, arg[i])
    else
      io.write("Query parameters cannot contain spaces: '" .. arg[i] .. "'\n")
      return 1
    end
  end

  -- Setup the UDP socket
  client = assert( socket.udp() )
  assert( client:settimeout(3) )

  -- Construct the query packet
  local query = "\255\255\255\255getservers " .. protocol
  for i=1,#params do
    query = query .. " " .. params[i]
  end

  destination = assert( socket.dns.toip(hostname) ) -- Resolve hostname to IP address for sending

  io.write("Requesting servers from " .. hostname .. ":" .. port .. "...\n")
  assert( client:sendto(query, destination, port) ) -- Send the request

  io.write([[

Server Name                             Map Name            Players   Game Type
-----------                             --------            -------   ---------
]])

  -- Listen for replies from the master server and any game servers
  while true do
    local msg,fromaddr,fromport = client:receivefrom()
    -- Ignore any errors/timeouts
    if msg ~= nil then
      -- Ensure packet begins with \255\255\255\255 and at least one more letter
      if msg:find("^\255\255\255\255%a") then
        --print("Valid packet from " .. fromaddr .. ":" .. fromport .. ", Length: " .. msg:len())
        msg = msg:sub(5)
        if startsWith(msg, "getserversResponse") then
          incomingGetServersResponse(msg, fromaddr, fromport)
        elseif startsWith(msg, "infoResponse") then
          incomingInfoResponse(msg, fromaddr, fromport)
        end
      end
    else
      --if fromaddr == "timeout" then
        break
      --end
    end
  end

  return 0
end

main()

--[[

Copyright (c) 2012 Dion Williams 

Permission is hereby granted, free of charge, to any person obtaining a copy of 
this software and associated documentation files (the "Software"), to deal in 
the Software without restriction, including without limitation the rights to 
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
of the Software, and to permit persons to whom the Software is furnished to do 
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all 
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
SOFTWARE.

--]]