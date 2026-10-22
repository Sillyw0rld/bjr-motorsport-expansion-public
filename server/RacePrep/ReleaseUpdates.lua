-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (c) 2026 Sillyw0rld
-- Console-only controls. Network/download work runs in the standalone process.
-- Release updates and optional mods (KTS, Fluid Spill, Dynamic Damage
-- Particles: checked, downloaded from their official pages, installed at the
-- next launcher start; owners can ignore the ones they don't want).
local U = {}
U.OPTIONAL = {kts=true, fluidspill=true, ddp=true}
function U.new(o)
    local self = {nextCheck=0}
    local function message(s) o.log('Updates: '..tostring(s)) end
    local statusFile, ignoreFile = o.path..'/optional-mods-status.json', o.path..'/optional-mods.json'
    -- action: generator flags; work: where the generator writes request-<id>.json
    local function launch(flags, work, starting)
        if self.pending then message('a request is already running; use bjrme update-status'); return end
        local exe='./bjrme-generator/bjrme-generator'..(o.windows and '.exe' or '')
        if not o.exists(exe) then message('standalone executable missing; use the distribution launcher/native package'); return end
        self.serial=(self.serial or 0)+1
        local request=tostring(o.now())..'-'..self.serial
        local idFlag=work=='.raceprep-update' and '--update-request-id ' or '--optional-request-id '
        local command='"'..exe..'" --beammp . '..flags..' '..idFlag..request..' > "'..work..'.log" 2>&1'
        o.execute(o.windows and ('start "" /B '..command) or (command..' &'))
        self.pending={started=o.now(),id=request,work=work}
        message(starting)
    end
    local function ignoredList()
        local d=o.read(ignoreFile) or {}
        local out={}
        for _,k in ipairs(type(d.ignore)=='table' and d.ignore or {}) do if U.OPTIONAL[k] then out[#out+1]=k end end
        return out
    end
    -- stop or resume reminders for one optional mod; the status file follows at once
    function self.ignore(key, on)
        if not U.OPTIONAL[key] then return false end
        local list={}
        for _,k in ipairs(ignoredList()) do if k~=key then list[#list+1]=k end end
        if on then list[#list+1]=key end
        table.sort(list)
        o.write(ignoreFile,{ignore=list})
        local status=o.read(statusFile)
        if type(status)=='table' then
            for _,m in ipairs(type(status.mods)=='table' and status.mods or {}) do if m.key==key then m.ignored=on and true or false end end
            local kept={}
            for _,line in ipairs(type(status.reminders)=='table' and status.reminders or {}) do
                if not (on and line:find('bjrme get '..key..'"',1,true)) then kept[#kept+1]=line end
            end
            status.reminders=kept
            o.write(statusFile,status)
        end
        return true
    end
    -- reminder lines from the last check (written by the launcher's preflight)
    function self.reminders()
        local status=o.read(statusFile)
        return type(status)=='table' and type(status.reminders)=='table' and status.reminders or {}
    end
    -- what Motorsport settings shows staff: mods still needing attention
    function self.optionalView()
        local status=o.read(statusFile)
        local out={}
        for _,m in ipairs(type(status)=='table' and type(status.mods)=='table' and status.mods or {}) do
            if U.OPTIONAL[m.key] and m.state~='current' and not m.ignored then
                out[#out+1]={key=m.key,name=m.name,state=m.state,installed=m.installed,latest=m.latest,page=m.page,why=m.why}
            end
        end
        return out
    end
    function self.command(input)
        if type(input)~='string' then return end
        local cmd=input:match('^%s*(.-)%s*$')
        -- "bjrme ..." (the old "raceprep ..." still works)
        local sub=cmd:match('^bjrme%s*(.-)$') or cmd:match('^raceprep%s*(.-)$')
        if not sub then return end
        local verb,key=sub:match('^optional%s+(%a+)%s+(%w+)$')
        local getKey=sub:match('^get%s+(%w+)$')
        if sub=='check-update' then launch('--update-check','.raceprep-update','checking the configured GitHub release')
        elseif sub=='update' then launch('--update-stage','.raceprep-update','checking/downloading a verified release; installation waits for the next launcher start')
        elseif sub=='update-status' then
            local result=o.read('.raceprep-update/status.json')
            message(type(result)=='table' and result.message or 'no result yet; releases: https://github.com/Sillyw0rld/bjr-motorsport-expansion-public/releases')
        elseif sub=='optional' then
            local lines=self.reminders()
            if #lines==0 then message('optional mods: nothing to do (installed at their tested versions, or ignored)') end
            for _,line in ipairs(lines) do message(line) end
            launch('--optional-check','.bjrme-optional','checking optional mods again')
        elseif (verb=='ignore' or verb=='unignore') and key then
            if self.ignore(key,verb=='ignore') then
                message(verb=='ignore' and ('no more reminders for '..key..' ("bjrme optional unignore '..key..'" brings them back)') or ('reminders for '..key..' are back'))
            else message('unknown optional mod "'..key..'": kts, fluidspill or ddp') end
        elseif getKey then
            if U.OPTIONAL[getKey] then launch('--optional-get '..getKey,'.bjrme-optional','downloading '..getKey..' from its official page; it installs at the next launcher start')
            else message('unknown optional mod "'..getKey..'": kts, fluidspill or ddp') end
        elseif sub=='help' or sub=='' then
            message('bjrme check-update | bjrme update | bjrme update-status | bjrme optional | bjrme optional ignore|unignore <mod> | bjrme get <mod> (mods: kts, fluidspill, ddp). Downloads stage only; stop BeamMP and start via the launcher to install.')
        else return end
        return 'BJR:ME command handled'
    end
    function self.tick()
        local now=o.now()
        if self.pending then
            local result=o.read(self.pending.work..'/request-'..self.pending.id..'.json')
            if type(result)=='table' and result.requestId==self.pending.id then
                message(result.message or result.status);self.pending=nil
            elseif now-self.pending.started>600 then
                message('request timed out; check '..self.pending.work..'.log before retrying');self.pending=nil
            end
        end
        if now>=self.nextCheck then
            local cfg=o.read(o.path..'/updates.json') or o.read(o.path..'/updates.example.json') or {}
            local interval=math.max(1,math.min(168,tonumber(cfg.checkEveryHours) or 24))*3600
            self.nextCheck=now+interval
            if cfg.enabled and cfg.repository and cfg.repository~='OWNER/REPOSITORY' then launch('--update-check','.raceprep-update','checking the configured GitHub release')
            elseif not self.placeholderShown then
                message('checker inactive until updates.json is configured: https://github.com/OWNER/REPOSITORY/releases')
                self.placeholderShown=true
            end
        end
    end
    return self
end
return U
